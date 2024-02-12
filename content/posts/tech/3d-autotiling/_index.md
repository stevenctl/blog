---
title: 3D Autotiling
---

<video src="demo.webm" autoplay muted loop></video>

I don't think I would have become interested in shooters if it weren't for Halo
3's forge mode. I probably logged 1000 hours in Minecraft when I was a kid (and
learned Java because of it!). Games that let you make stuff are the best. Making
games is even better. After a few years focusing on my career in network programming
I decided to revisit games, this time looking at 3D.

I picked up a book on 3D modeling and then tried to start making a game.
Building a castle felt a bit tedious to me, even with a modular kitbash asset pack.
In 2D and 3D, I hate rotating and aligning tiles to fit. 

In [Townscaper](https://www.townscapergame.com/), it's very easy to build something
that looks "correct". I wanted to replicate that experience in a level editor. This
led me down a rabbit hole into exploring different procedural generation techniques:
Wave Function Collapse, Marching Cubes for terrain, Heightmap Terrain. The hardest part was
modifying them to make them artist controllable.

This short series covers my Wave Function Collapse implementation. I've implemented 
the core algorithm 4 times. First in Blender/Python intending to export to Unity/C#. 
Unity had issues on my Linux machine so I tried Bevy/Rust. Turns out an editor is a 
valuable debugging tool and I finally have a solid working version in Godot. 

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
        link="05-optimization"
        title="Part 5: Optimizations"
    >}}
{{</ cards >}}



