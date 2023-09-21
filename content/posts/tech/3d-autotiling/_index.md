---
title: 3D Autotiling
---

<video src="demo.mp4" autoplay muted loop></video>

I picked up a book on 3D modeling and then tried to start making a game.
Building a castle felt a bit tedious to me, even with a modular kit. In 2D and
3D, I hate rotating and aligning tiles to fit. 

My impatience led me down a months-long rabbit hole learning about procedural
generation. I've come up with what a pretty decent Wave Function Collapse
implementation, including Blender tools to help with asset creation. I
implemented the core algorithm 4 times. First in Blender/Python intending to
export to Unity/C#. Unity was annoying so I tried Bevy/Rust. Turns out an
editor is a valuable debugging tool and I finally have a solid working version
in Godot. The ultimate goal is a grade of polish with which end users can
create in-game or in-engine levels.

I don't think I would have become interested in shooters if it weren't for Halo
3's forge mode. I probably logged 1000 hours in Minecraft when I was a kid (and
learned Java because of it!). Games that let you make stuff are the best.

In a future post I will show a complete demo of the workflow starting from
Blender, to the in-engine builder and finally having a character run around
in a scene created with the builder. 

---

## Writeup

The following posts are a technical breakdown of stepping stones
towards a decent WFC workflow. They still need some editing,
but I think they're cohesive enough to share.

{{< cards >}}
    {{< card
        link="01-marching-squares"
        title="Part 1: 2D Marching Squares"
    >}}
    {{< card
        link="02-basic-wfc"
        title="Part 2: Basic Overview of WFC"
    >}}
    {{< card
        link="03-driven-wfc"
        title="Part 3: User Driven WFC"
    >}}
    {{< card
        link="04-generating-tiles"
        title="Part 4: Generating a Tileset"
    >}}
    {{< card
        link="05-sockets"
        title="Part 5: Simpler Adjacency"
    >}}
{{</ cards >}}



