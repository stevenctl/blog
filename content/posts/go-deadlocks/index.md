---
title: "debugging Go deadlocks"
date: 2026-01-13
type: tech
tags: ["go"]
---

**UPDATE:** I made this into a small Go module: [https://github.com/stevenctl/deadlog](https://github.com/stevenctl/deadlog).
It is a drop in replacement for `sync.Mutex` and `sync.RWMutex`, with the option to call the returned `unlock` closure
if you want to track unreleased locks. Don't run with this in production, it's only for debugging deadlocks.


Multiple times, I've had to debug deadlocks in some Go code. Even though Go's
`-race` flag when running tests can detect deadlocks, in my experience it
hasn't caught the ones that drive me crazy with flaky or fast tests
(~500ms-2s).

It's definitely a tricky class of bug to track down, especially when you
weren't the one who wrote the code or the design of the system is (too)
complex.

Multiple times now, I've resorted to wrapping `sync.Mutex` or `sync.RWMutex`
with one that has logging:

```go
type loggedMu struct {
    mu sync.Mutex
	context string
}

func (lm *loggedMu) Lock() {
	id := rand.IntN(9999999)
	log.Infof("LOGMU LOCK START (%s) %d", lm.context, id)
	lm.mu.Lock()
	log.Infof("LOGMU LOCK ACQUIRED (%s) %d", lm.context, id)
}
```

We need some way to correlate the log lines for a single attempt to lock.

That's not quite enough to find which lock hasn't been released. For that we can
return a unlock function:

```go
func (lm *loggedMu) Lock() func() {
    id := rand.IntN(9999999)
    log.Infof("LOGMU LOCK START (%s) %d", lm.context, id)
    lm.mu.Lock()
    log.Infof("LOGMU LOCK ACQUIRED (%s) %d", lm.context, id)
    return func() {
        log.Infof("LOGMU LOCK RELEASED (%s) %d", lm.context, id)
        lm.mu.Unlock()
    }
}
```

To get a bit more info, we can accept a name for context on the mutex:

```go
func (lm *loggedMu) LockNamed(name string) func() {
	id := rand.IntN(9999999)
	log.Infof("LOGMU LOCK START (%s) %s %d", lm.context, name, id)
	lm.mu.Lock()
	log.Infof("LOGMU LOCK ACQUIRED (%s) %s %d", lm.context, name, id)
	return func() {
		log.Infof("LOGMU LOCK RELEASED (%s) %s %d", lm.context, name, id)
		lm.mu.Unlock()
	}
}
```

An annoying case is when getters lock for reading, and callers already holding
a lock don't realize that and end up causing the deadlock:

```go
func (s *SomeService) GetThing(id string) *Thing {
	defer s.mu.RLockNamed("GetThing")()
	return s.things[id]
}

func (s *SomeService) Recompute() {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.computed = doComputation(s.GetThing("foo"), s.GetThing("bar"))
}
```

Not only is this a frequent source of deadlocks, our `RLockNamed` context
doesn't really help us find the root of the problem. We can add some stack
information to the log to help correlate that info:

```go
func getCallerChain(skip, depth int) string {
	if depth <= 0 {
		return ""
	}
	pcs := make([]uintptr, depth)
	n := runtime.Callers(skip, pcs)
	if n == 0 {
		return ""
	}
	frames := runtime.CallersFrames(pcs[:n])

	var parts []string
	for {
		frame, more := frames.Next()
		name := frame.Function
		if idx := strings.LastIndex(name, "."); idx != -1 {
			name = name[idx+1:]
		}
		parts = append(parts, fmt.Sprintf("%s:%d", name, frame.Line))
		if !more || len(parts) >= depth {
			break
		}
	}
	return strings.Join(parts, " <- ")
}
```

Using some [ script
](https://gist.github.com/stevenctl/ff03d25490e430658b3fae627a5a0e97#file-analyze_locks-sh) to analyze the logs, this should allow us to count instances of
some "lock attempt ID" and make detect issues:

1. We're stuck waiting if we see `LOCK START` but not `LOCK ACQUIRED`
2. We're stuck holding if we see `LOCK ACQUIRED` but not `LOCK RELEASED` (assuming we used the unlock function)

```
===============================================
LOCK CONTENTION ANALYSIS
===============================================

=== STUCK: Started but never acquired (waiting for lock) ===
RLOCK | c1   | GetExampleThing           | ID: 7339384
LOCK  | c1   | example-event-handler     | ID: 5543602
RLOCK | c1   | GetExampleThing           | ID: 6593621
RLOCK | c3   | GetExampleThing           | ID: 4974634
LOCK  | c3   | example-reconcile         | ID: 1959832

=== HELD: Acquired but never released (holding lock) ===
RLOCK | c3   | reconcileExampleStatus    | ID: 5377378
RLOCK | c1   | reconcileExampleStatus    | ID: 2873953

=== SUMMARY ===
Stuck waiting: 5
Held (named):  2`
```

My process for using this usually starts with just the basic logging wrapper,
we're likely only stuck waiting if we're stuck holding. I can detect that without changing anything
but the type of mutex to my wrapper. Then, if I actually see a deadlock, I'll update callsites to use
the named locks with the wrapped `Unlock` so I can see who was the one holding the unreleased lock.

This code should have been much simpler in the first place. The fact that I had
to break out this approach is one sign. Another sign is that I initially told
Claude Code "fix this flaky test" and it consumed like 300k tokens and talked
itself in circles.

LLMs/coding agents are usually pretty good at debugging when they are given a
specific area of the code to focus on, fast ways to run tests, and a way to add
println debugging. When I came back to that tab and saw it struggling, I
started a fresh session and told it to add this wrapper to the mutex and how to
run the tests. Within 5 minutes it found the deadlock, the root cause and
restructured the code to avoid the deadlock and make it a little harder for a
future dev to accidentally reintroduce it.

Deadlocks suck to debug, but LLMs and giving the LLMs enough context makes an otherwise
subtle bug pretty easy to find without reading over some convoluted code over and over.

