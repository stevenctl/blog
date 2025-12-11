---
title: "mini apps"
date: 2025-12-11
type: tech
tags: ["random"]
---

# mini-apps

Try them out yourself:

https://stevenctl.github.io/mini-apps/

or

```bash
# git clone git@github.com:stevenctl/mini-apps
git clone https://github.com/stevenctl/mini-apps
# try opening $pwd/index.html in your browser
# or for some apps, you need to run a webserver:
python -m http.server 9999
# then open http://localhost:9999 in your browser
```


### Motivation

For the most part, when you want a simple app that does one thing, you will
have to search pretty hard. Most of the stuff out there is crammed with
features you didn't ask for, ads, some kind of login and probably other types
of bloat I can't think of right now. Oh, AI features you didn't want.

For example, I want a macro tracker app. Super simple requirement:
- fast UI that lets me input 3 numbers (fat, protein, carbs) and maybe a food name.
- bonus would be something to scan a barcode or nutrion label with my phone camera
- extra bonus would be to sync the data across devices

A quick search shows me some not amazing options (for my minimal needs):
* [MacroFactor](https://macrofactorapp.com/macrofactor/)
  - 250MB! AI recognition of pictures of entire meals. Calculators I don't
    want.
- [MyFitnessPal](https://www.myfitnesspal.com/)
  - Even bigger at 280MB! Ads, subscriptions, social features I don't want.
- [Stupid Simple Macro Tracker](https://www.mystupidsimpleapp.com/stupid-simple-macros)
  - 130MB is better. I like that the premium version is a one time purchase. The UI is pretty crowded
    compared to what I need, but this actually seems decent.

I am _not_ saying the people who create these apps don't deserve to be paid for
their work, and that these apps are bad. Clearly there is a market for them.
They're just not what I'm looking for. Using AI, we can free ourselves from
subscriptions, social features, and AI jamming itself into simple apps. Just
make the exact app you want. Being a programmer helps a lot here when the AI
starts going down the wrong path.


#### Speed (as a user)

I really love local-first software. Local-only software is even better. Even
though these apps can be accessed online via github pages, you can run them
locally with minimal or no setup. The data backing them should load very very
fast.

#### Speed (as a developer)

The code is 70-90% AI generated. I just had some stuff that I wanted to use
and iterating on this with Claude Code was a fun thing to do while I waited
for my actual work/projects to compile, run tests, etc.

I really love the idea of [ generative UI
](https://research.google/blog/generative-ui-a-rich-custom-visual-interactive-user-experience-for-any-prompt/),
but I think the on-demand stuff isn't going to be very pleasant to use most of
the time. Theres a reason a lot of designers are not the programmers, and even
programmers who are designers don't one-shot it on their first implementation
of the app, going straight to writing code.

Eventually, I'd like to have a more sophisticated approach to building these
apps. There should be some kind of shared component library, and maybe some
standards so styling can be adjusted while re-using those building blocks. This
[blog post by tambo](https://tambo.co/blog/posts/what-is-generative-ui) touches
on that a bit. The "on-demand" UIs would be much more pleasant if the
components they're built from where designed and iterated by huamans
(regardless of LLM assistance in implementation).

Even without on-demand generation, having building blocks would probably speed
up the iteration process, but I wanted to see how well things worked with zero
dependencies or build step.

Data is the source of truth, and the UI organizes itself around that.
