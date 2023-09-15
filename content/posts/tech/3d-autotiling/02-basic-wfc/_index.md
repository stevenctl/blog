---
title: Basic Wave Function Collapse
weight: 2
---

![wfc generation in blender](generate.mp4)

This 3D autotiling project started when I stumbled on [Martin Donald's Wave
Function Collapse video](https://www.youtube.com/watch?v=2SuvO4Gi7uY). The idea
was explained so well that I had to try it out. 

In this post I will attempt to outline the high level structure of a Wave
Function Collapse implementation with a bit of psudo-Python. The following
isn't really intended to be a tutorial, but more of an introduction that sets
the stage for some future posts.

## Types

We have a few foundational types that make up the implementation:

### Prototypes

```python
class Prototype:
    name: str
    mesh: str
    rotation: int

    # sockets
    north: str
    east: str
    south: str
    west: str
    top: str
    bottom: str
```

A prototype represents a possible choice to put somewhere in the grid. We will
have 4 prototypes for each tile in our tileset, one for each 90 degree
rotation.

### Sockets

On each of the 6 faces we will have a socket. These identify which `Prototype`s
can connect to eachother in each direction. The socket is a representation of
what we see when we look at one face of the tile's bounding box.


![highligted socket](socket.jpg)

For the north and south or east and west sockets to match, they must be mirrors
of one another. For a vertical face's socket to match (top to bottom) the
sockets must be identical. Sockets are arbitrary strings, except for the
suffixes on horizontal faces' sockets: `s` (symmetrical) and `f` (flipped).

```python
def compatible_sockets(face, a, b) -> bool:
    # symmetrical faces should be identical
    if face in {"top", "bottom"} or a.endswith("s"):
        return a == b     
    flipped_b = socket[:-1] if socket.endswith("f") else b + "f"
    return a == flipped(b)
```

### Cells

```python
class Cell:
    possibilities: list[Prototype]
```

A cell is one element in a `Grid`, which is just a collection of `Cell`s. 

### Grid

Turns out there are a lot of ways to represent the `Grid`. 

It could be a 3D array:

```python
class Grid:
    grid: list[list[list[Cell]]]
```

Or for an infinite grid, a map that lazily populated:

```python
class Grid:
    grid: dict[Vec3, Cell]

    def __getitem__(self, coord: Vec3):
        if key not in self.grid:
            self.grid[coord] = Cell()
        return self.grid[coord]
```

It doesn't really batter as long as we can look things up using a 3D integer coordinate.

## Implementation

```python
def solve():
    work_list = []
    solved = False
    iteration = 0
    while not solved and iteration < MAX_ITERATIONS:
        iteration += 1

        cell, coord = grid.find_min_entropy()
        if cell is None:
            solved = True
            break

        cell.collapse()
        work_list.append(coord)
        while len(work_list) > 0:
            work_list += propagate(work_list.pop())
```

This is the main structure of the program. Make a random selection in one of the cells
recursively propagate that out and repeat until every cell has only one possibility.
You can run the outer loop by hand in this [web demo](https://bolddunkley.itch.io/wfc-mixed) 
from Martin Donald.

### Collapse 

In this algorithm, "entropy" is a cute name for the length of a `Cell`'s
possibility list. Zero means there is a contradiction and we will never be able
to solve the `Grid`. One means we know the `Prototype` that we've chosen for
this cell. In each iteration, we find the unsolved Cell we're most certain
about:

```python
def min_entropy(self) -> Cell:
    def entropy(cell):
        if cell.entropy() < 2:
            return math.inf
        return cell.entropy()
    return min(self.grid, key=entropy)

```

Then we "collapse" it's possibilities into a random choice:

```python
def collapse(self):
    idx = randint(0, len(self.possibilities) - 1)
    self.possibilities = [self.possibilities[idx]]
```

### Propagate

```python
def propagate(coord):
    cur_cell = self.grid.get(cur_coord)
    changed_neighbors = []
    for direction in opposing_faces.keys():
        next_coord = add_vec3(cur_coord, face_deltas[direction])
        if not self.grid.is_in_bounds(next_coord):
            continue
        next_cell = self.grid.get(next_coord)
        changed = grid[next_cell].constrain_to_neighbor(cur_cell, direction)
        if changed:
            changed_neighbors.append(next_coord)
            self.propagation_stack.append(next_coord)
    return changed_neighbors
```

Any time we change the possibility list of one cell,
the neighboring cells are possibly affected. We reduce the possibility list
of each neighboring cell with `constrain_to_neighbor` and if that causes
a change, we will have to propagate to _that_ cell's neighbors as well.


### Constrain

```python
def constrain_to_neighbor(self, cell: Cell, face: str):
    old = len(self.possibilities)
    self.possibilities = [
        p
        for p in self.possibilities[]
        if compatible_sockets(my_face, p[my_face], cell[face])
    ]
    return old != len(self.possibilities)
```

Here we reduce the possiblity list to only include `Prototype`s that are compatible
on the opposing face.

There are far more efficient ways of doing this, like setting up an adjacency
table. This is also the part of the algorithm that is most likely to have edge
cases to help guide the algorithm's behavior to produce specific results.


## Conclusion

While this post was mostly psuedo code, it matches up pretty well to my first
WFC attempt. The code is available
[here](https://github.com/stevenctl/basic-wfc-blender) as well as a sample
Blender file you can use to run it. This implementation has a lot of issues and
isn't scalable, but I did find I use for it that's covered in a later post.

