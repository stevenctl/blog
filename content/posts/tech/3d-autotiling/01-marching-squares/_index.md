+++
title = "2D Autotiling with Simplified Marching Squares"
weight = 1
+++

<video src="demo.mp4" autoplay muted loop></video>

## Motivation

Although this is the first post in the series, I'm actually writing this code
last. I haven't written the 2D part before, but it's useful for understanding
how the 3D stuff works. There are lots of [better choices for 2D
autotiling](https://www.boristhebrave.com/2021/09/12/beyond-basic-autotiling/).
This is just a baby step.

## Marching Squares Overview

[Marching Squares](https://en.wikipedia.org/wiki/Marching_squares) and it's 3D
cousin [Marching Cubes](https://en.wikipedia.org/wiki/Marching_cubes) are both
algorithms for converting an array of scalar values into a shape or mesh. These
algorithms are pretty robust and with high enough resolution and smart
interpolation they will produce a very nice output.

Both algorithms operate on a dual grid. This means we consider both the actual
cells of the grid and the corners of each cell separately. In this case the
corners of the grid represent the "density" information. This could either be a
`0` or `1` telling us if the point is filled or empty, or it could be an
arbitrary scalar value telling us _how_ full it is.

![scalar grid](grid.jpg)

The goal here is 2D autotiling, not generating any kind of smooth mesh. So we
can treat the corners as either filled or empty. We have 4 corners per cell with
two possibilities. So 2⁴ total combinations.

![cases](cases.jpg)

Depending on the artstyle, you may not need unique tiles for the same shape in
different directions. If we remove cases that are mirrors or rotations of
others, we only have 5 things to draw. Notice in that `2b`, the diagonal case
can either be a gap or a bridge. In marching squares this is called a saddle
point. We're just going to make that an artistic/gameplay choice here.

![unique tiles](uniq.jpg)

## Implementation

For this tutorial I'm going to use Godot with GDScript. Feel free to follow
along with whatever you're comfortable with.

### Lookup Table

We can think about each corner as being one bit of a 4-bit integer. Starting in
the top left, moving in clockwise order we will set the least signficant bit.

![binary enumeration](binary.jpg)

We could either create 16 tiles and map each case 1 to 1 or we could draw 5
tiles (6 if you count the empty case) and rotate and flip them as needed. The
tileset below has 6 48x48 tiles.

![tileset](tileset.png)

Since there are only 16 cases, we can manually write out the conversions. The
`tile` is the index from left to right and `rotation` is the number of 90 degree
clockwise turns.

```gdscript
var lookup = {
	# empty
	0: {"tile": 0, "rotation": 0}, 

	# corner 
	1: {"tile": 1, "rotation": 0},
	8: {"tile": 1, "rotation": 1},
	4: {"tile": 1, "rotation": 2},
	2: {"tile": 1, "rotation": 3},

	# edge 
	3: {"tile": 2, "rotation": 0},
	6: {"tile": 2, "rotation": 3},
	9: {"tile": 2, "rotation": 1},
	12: {"tile": 2, "rotation": 2},

	# diagonal 
	5: {"tile": 3, "rotation": 0},
	10: {"tile": 3, "rotation": 1},

	# bend
	7: {"tile": 4, "rotation": 0},
	11: {"tile": 4, "rotation": 1},
	13: {"tile": 4, "rotation": 2},
	14: {"tile": 4, "rotation": 3},

	# full
	15: {"tile": 5, "rotation": 0},
}
```

{{< callout >}}
Here I a dictionary to make it easier to write by hand.
Usually you'll see this as an array, especially when
passing it to a compute shader.
{{< /callout >}}

### Cursor

<video src="step-1.mp4" autoplay muted loop></video>

Pretty simple:

```gdscript
func _ready():
	cursor = ColorRect.new()
	cursor.color = Color(1, 0, 0, 0.5)
	cursor.size = Vector2(TILE_SIZE, TILE_SIZE)
	add_child(self.cursor)

func _input(event):
	if event is InputEventMouse:
		var rounded = Vector2i(event.position / TILE_SIZE) * TILE_SIZE
		self.cursor.position = rounded
		if event is InputEventMouseButton and event.is_pressed():
			_toggle(rounded)
```

### Bit Flipping

First we add a top level dictionary:

```gdscript
// Vector2i -> int
var tiles = {}
```

This will be keyed by the `Vector2i` where we will draw the tile.
The value is the index to use in the lookup table.

Next, when we click somewhere on the grid we will flip a bit in the 4
surrounding cells. The cells we interact with are more like the corners of 4
cells that we draw on. The order matters. Since the bottom right corner uses the
first bit, we start with that and then go counter clockwise.

```gdscript
var offsets =  [
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(0, 0), 
	Vector2i(1, 0), 
]

func _toggle(pos: Vector2i):
	var grid_coord = pos / TILE_SIZE
	
	for i in range(len(offsets)):
		var offset_coord = grid_coord + offsets[i]
		if offset_coord not in tiles:
			tiles[offset_coord] = 0
		tiles[offset_coord] ^= 1 << i
```

### Lookup and Draw

Finally, we can do a lookup using the index which we just modified.

```gdscript
func _toggle(pos: Vector2i):
    ...
    for i in range(len(offsets)):
        # flip a bit 

    	var s = get_node_or_null(str(offset_coord))
		if not s:
			s = Sprite2D.new()
			s.name = str(offset_coord)
			s.texture = tileset
			s.region_enabled = true
			s.position = (offset_coord + Vector2i.DOWN) * TILE_SIZE
			add_child(s)
		
		if tiles[offset_coord] == 0:
			s.queue_free()
		else:
			var tile = lookup[tiles[offset_coord]]		
			s.region_rect = Rect2(tile["tile"] * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE)		
			s.rotation_degrees = 90 * tile["rotation"]
```
