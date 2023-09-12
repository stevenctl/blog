---
title: 3D Autotiling
---

## Preface

It took a few attempts to figure out how to organize this. At first it was
written in the order of the things I tried out. I started with a very complex
thing that led me to learn some more basic approaches. I will build from those
foundational concepts up to the current state of my project.

A while back I picked up a book on 3D modeling. It made me think I could make 3D
games. Turns out there's a lot to it. And I got frustrated at my first attempt
to kitbash some modular castle set into something decent. It didn't feel fun
rotating and aligning everything properly.

I got sidetracked for months learning a bit about procedural generation because
I wanted a more interactive workflow. I implemented Marching Cubes in compute
shaders, Heightmaps using compute and vertex shaders and my favorite thing: Wave
Function Collapse with a simplified Marching Cubes. 3D autotiling was the sweet
spot I was looking for.

This project has exposed me to a bunch of areas in the graphics and asset
creation pipeline. I'm pretty happy with where it is right now and I'm hoping I
can polish it off as a solid tool for making small and big games. The ultimate
goal is a level of polish that can be exposed to end users to create their own
levels. I don't think I would have become interested in shooters if it weren't
for Halo 3's forge mode. I probably logged 1000 hours in Minecraft when I was a
kid (and learned Java because of it!). Games that let you make stuff are the
best.

---

## Writeup

The following will attempt to semi-interactive where possible. Unfortunately I
did a lot in Godot 4.0 which doesn't support web export for Mono/C# yet. These
aren't intended to be full on tutorials, but it should be possible to fill in
the gaps if I explained things well enough.

{{< cards >}}
    {{< card
        link="01-marching-squares"
        title="Part 1: 2D Autotling with Marching Squares"
    >}}
{{</ cards >}}

## First Drafts

The following are brain dumps that will be rewritten.

{{< cards >}}
    {{< card
        link="01-marching-squares"
        title="Part 1: 2D Autotling with Marching Squares"
    >}}
{{</ cards >}}
