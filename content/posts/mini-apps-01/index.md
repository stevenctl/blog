---
title: "building random small things"
date: 2026-05-31
type: tech
tags: ["random"]
---

# building random small things

At this point we all know that AI lets us build whatever we want when we want it.
It's especially nice when I have small things I want for myseelf and I wouldn't have
otherwise spent the time bootstrapping and polishing them to the point that they're
daily-drivable.

The reason I frequently feel the need for such tiny apps is that most things available
at the top of whatever SEO optimized search are pretty bloated. For example, a fitness/macro tracker:

* [MacroFactor](https://macrofactorapp.com/macrofactor/)
  - 250MB! AI recognition of pictures of entire meals. Calculators I don't
    want.
- [MyFitnessPal](https://www.myfitnesspal.com/)
  - Even bigger at 280MB! Ads, subscriptions, social features I don't want.
- [Stupid Simple Macro Tracker](https://www.mystupidsimpleapp.com/stupid-simple-macros)
  - 130MB is better. I like that the premium version is a one time purchase. The UI is pretty crowded
    compared to what I need, but this actually seems decent.

Not that these apps are necessarily bad, they aren't what I want. I jsut want a glorified
notebook that would automatically sum some things up, and MAYBE automatically import data from a barcode
or OCR the Nutrition Facts. This is something any AI coding agent could whip up in the background while I
focus on something else.

# local first

I really like local-first software. It is insanely responsive, it works in airplane mode
and has better privacy. This is how I built [Bookchoy](https://bookchoy.app) and this is how I would build ~any
mini app. sqlite runs everywheere and is fast.

# what I made

* File based TODO/kanban board
* RSS reader with a localstorage based store for tracking what I read or bookmarked.
* Neovim plugin for doing Chinese-English dictionary lookups using LSP hover

Try them out yourself:

https://stevenctl.github.io/mini-apps/
https://github.com/stevenctl/bookchoy.nvim

or

```bash
# git clone git@github.com:stevenctl/mini-apps
git clone https://github.com/stevenctl/mini-apps
# try opening $pwd/index.html in your browser
# or for some apps, you need to run a webserver:
python -m http.server 9999
# then open http://localhost:9999 in your browser
```
