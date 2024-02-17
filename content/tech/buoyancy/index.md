---
title: Faking Buoyancy
type: tech
---

{{<video "demo.webm" >}}

For the intro to a game I'm working on, I decided to put the player on a pirate
ship. If (when) the player tries to jump off the ship, we could prevent them,
have them reset/die, or swim. I decided on the simplest option, resetting them.

Next, I moved on to making the boat rock with the waves. At first, I just made
the X-axis rotation oscillate between two values, and this worked fine. Recently,
I discovered [Acerola's](https://youtube.com/@Acerola_t) amazing channel. In
[one of his videos](https://www.youtube.com/watch?v=ja8yCvXzw2c) he mentions
using plane fitting algorithms as a method for faking buoyancy. This inspired
me to add a bit more fidelity to the rocking.

## Floating

Plane fitting is a 3D form of [line
fitting](https://en.wikipedia.org/wiki/Line_fitting); a process of finding the
straight line that can best fit some data points. Acerola's example used a
bunch of samples from the bottom of an object as data points and fed them to
what I assume was a "proper" plane fitting algorithm such as [Least
Squares](https://en.wikipedia.org/wiki/Least_squares) or [Principal Component
Analysis](https://en.wikipedia.org/wiki/Principal_component_analysis). 

Those seemed somewhat complicated to fully grasp. It's probably overkill for my
stylized game. My requirements are minimal:

* Orient the object to rest on the water's curve surface.
* Put the object (near) the top of the water.

Starting with the orientation, we can look at this very similarly to looking
for the normal of a heightmap. Our waves are just a vertex-displaced plane,
where the y-displacement is defined by some function. There are a few options for
computing the normals:

* Using small finite differences to approximate the normals at a single point.
* Use central differences according to the size of the object to calculate the average normals.
* Leverage the cross product to find our normals according to the size of the object.

## Small Finite Differences

Finite differences is a method of estimating the slope of a function at a given
point. It's the "rise over run" concept from elementary school. For our 3D
curve, we'll check the height (y) at 3 points. One center point, one to the
left and one forward. If we use a very small step, we can estimate a very local
slope.

{{<katex>}}$$\Delta x ~= \frac{w(x, z) - w(x + S, z)}{S}$$
{{<katex>}}$$\Delta z ~= \frac{w(x, z) - w(x, z + S)}{S}$$

To get a normal from these two slopes, we can take the [cross product](https://en.wikipedia.org/wiki/Cross_product),
an operation that gives a 3rd vector perpendicular to both of the given vectors:

{{<katex>}}$$
\vec n =
\begin{bmatrix}
    S \\
    \Delta x \\
    0
\end{bmatrix}
\times
\begin{bmatrix}
    0 \\
    \Delta z \\
    S
\end{bmatrix}
$$

While this gives a very accurate approximation, it might be too accurate. When an
object is longer than some concave part of the curve, this increases the likelyhood
that we cut through the surface of the water.

![finite_diffs](finite_diffs.png)

## Object-Sized Finite Differences

To mitigate this, we can take the size of our object into account
when computing the differences. Supplying a width and length for
our object we define a plane or rectangle parallel with the
ground. The formulas just need a slight adjustment:

{{<katex>}}$$\Delta x ~= \frac{w(x - 0.5W, z) - w(x + 0.5W, z)}{W}$$
{{<katex>}}$$\Delta z ~= \frac{w(x, z - 0.5L) - w(x, z + 0.5L)}{L}$$

{{<katex>}}$$
\vec n =
\begin{bmatrix}
    W \\
    \Delta x \\
    0
\end{bmatrix}
\times
\begin{bmatrix}
    0 \\
    \Delta z \\
    L
\end{bmatrix}
$$

Notice that there are now four samples, and they all go in
different directions. This is a version of finite differences
called central differences. From these samples, if we rotate our
object then have a plane that _could_ fit on the wave but it sits
underneath, tangent to the wave's curve. This is fine in convex
scenarios, but it will lie underneath the curve in a concave area.
The adjusted position is the mean of our samples.

{{<katex>}} $$
y' = \frac{w(x - 0.5W, z) + w(x + 0.5W, z) + w(x, z + .5L) + w(x, z - .5L)}{4}
$$

{{< gallery >}}
    <img src="finite_diffs_width.png" class="grid-w50"/>
    <img src="adjust_pos.png" class="grid-w50"/>
{{< /gallery >}}

In the case where our rectangle spans across a convex area of the curve, this will
move us further down into the water. Using the higher of our adjusted value and the
height at the center of the rectangle easily mitigates this.

{{<katex>}} $$
y'' = \max(y', w(x, y))
$$

{{< gallery >}}
    <img src="convex_case.png" class="grid-w50"/>
    <img src="convex_case_fix.png" class="grid-w50"/>
{{< /gallery >}}

All of this, in code, looks like this:

```gdscript
func fit_plane(plane: Node3D, size: Vector2, strength: float) -> Transform3D:
    # take samples
    var center = plane.global_position
    var left = _wave(center + Vector3.LEFT * size.x / 2)
    var right = _wave(center + Vector3.RIGHT * size.x / 2)
    var front = _wave(center + Vector3.FORWARD * size.y / 2)
    var back = _wave(center + Vector3.BACK * size.y / 2)

    # compute the normal
    var dx = right -left
    var dz = back-front
    var normal = -Vector3(size.x, dx, 0).cross(Vector3(0, dz, size.y)).normalized()

    # place the object
    var surface_point = center
    var sample_mean = (left + right + front + back) / 4)
    var surface_point.y = max(_wave(center.y), sample_mean) 

    # create a transform
	var rotation_axis = Vector3.UP.cross(normal).normalized()
	var rotation_angle = Vector3.UP.angle_to(normal)
	if rotation_axis.length_squared() < .1:
		rotation_axis = Vector3.RIGHT
	return Transform3D(Basis(rotation_axis.normalized(), rotation_angle), surface_point)
```

## Triangles in a Quad

While the central differences approach works very well, it doesn't
handle the subtle rotation across the shorter part of our
rectangle. The samples all lie on the midpoints of the sides of
the triangles, creating a diamond shape. Sampling at the corners
will more accurately balance the object on the surface,
[projecting](https://www.desmos.com/3d/89a779a469) the entire
shape onto the curve.

![projection](projection.png)

We can get a pretty accurate normal by averaging the cross
products of the sides of each of the triangles formed by
{{<katex>}}\\(P_w\\) and the rectangle's corners. Using just the
front and back yields good enough results.

{{<katex>}}$$
\frac{\vec{AP_w} \times \vec{BP_w} + \vec{CP_w} \times \vec{DP_w}}
{2}
$$

In code, this looks like:

```gdscript
func fit_plane(center: Vector3, size: Vector2) -> Transform3D:
	# form corners of the axis-aligned plane
    var front_r = center + Vector3(size.x, 0, size.y)
    var front_l = center + Vector3(-size.x, 0, size.y)
    var back_r = center + Vector3(size.x, 0, -size.y)
    var back_l = center + Vector3(-size.x, 0, -size.y)

	# project the points onto the wave
	front_r.y = _wave(front_r)
	front_l.y = _wave(front_l)
	back_l.y = _wave(back_l)
	back_r.y = _wave(back_r)
	center.y = _wave(center)

	# front normal
	var v1 = front_l - center;
	var v2 = front_r - center;
	var normal_f = v1.cross(v2).normalized();

	# back normal
	v1 = back_r - center;
	v2 = back_l - center;
	var normal_b = v1.cross(v2).normalized();

	# rotation based on average of cross products
	var normal = (normal_b + normal_f) / 2.0;
```

{{< gallery >}}
    <img src="backbias.png" class="grid-w33"/>
    <img src="averaged.png" class="grid-w33"/>
    <img src="frontbias.png" class="grid-w33"/>
{{< /gallery >}}

The left side uses only `normal_b` and the right side uses `normal_f`. The center is the
averaged normal. In my opinion, it looks much better.

## Fixing Rotation and Scale

Our calculation is still inaccurate, especially if the plane we're
using isn't a square. We need to remember to take the parent
transforms into account. This means multiplying our rectangle size
by the object's scale.

Anywhere we use the `size` of our rectangle, we'll also need to
rotate. Also, if using the "avreage of triangles" method to compute the normal,
the rotation must be undone.

```gdscript
func fit_plane(plane: Node3D, size: Vector2) -> Transform3D:
	size *= Math.vec2(plane.scale)

    # samples for "average of triangles"
    var front_r = center + Vector3(size.x, 0, size.y).rotated(Vector3.UP, plane.global_rotation.y)
    var front_l = center + Vector3(-size.x, 0, size.y).rotated(Vector3.UP, plane.global_rotation.y)
    var back_r = center + Vector3(size.x, 0, -size.y).rotated(Vector3.UP, plane.global_rotation.y)
    var back_l = center + Vector3(-size.x, 0, -size.y).rotated(Vector3.UP, plane.global_rotation.y)

    # samples for "object sized finite differences"
	var left = _wave(center + (Vector3.LEFT * size.x / 2).rotated(Vector3.UP, plane.global_rotation.y))
	var right = _wave(center + (Vector3.RIGHT * size.x / 2).rotated(Vector3.UP, plane.global_rotation.y))
	var front = _wave(center + (Vector3.FORWARD * size.y / 2).rotated(Vector3.UP, plane.global_rotation.y))
	var back = _wave(center + (Vector3.BACK * size.y / 2).rotated(Vector3.UP, plane.global_rotation.y))

    # only needed for the triangles approach of calculating normal 
	var normal = ((normal_b + normal_f) / 2.0).rotated(Vector3.UP, -plane.global_rotation.y).normalized()

```


{{< gallery >}}
    <img src="broken_rot.png" class="grid-w50"/>
    <img src="fixed_rot.png" class="grid-w50"/>
{{< /gallery >}}

## Positioning and Movement

Now that our plane faces the right direction, we want to put it at the surface
of the water. We could choose to use the point on the curve under the center of
the plane, {{<katex>}}\\(P_w\\). 

```gdscript
var surface_pos = center.y
```

This works extremely well for how simple it is, but we can take it further.
Waves usually move things, right? How can we capture the force created by a
wave? The amplitude of the wave should affect the strength of the push we give.
It sounds like we need to look at the slope. This means we need the derivative
of our wave's function. 

The current wave is defined by:

{{<katex>}}$$w\left(x,y\right)=H\cdot e^{\sin\left(\sqrt{x^{2}+y^{2}}\right)+\sin\left(y\right)}$$

Using this intermediate term:

{{<katex>}}$$d = \sqrt{\left(x^{2}+y^{2}\right)}$$

So that our [partial
derivatives](https://www.wolframalpha.com/input?i=derivative+of+e%5E%28sin%28sqrt%28x%5E2%2By%5E2%29%29+%2B+sin%28y%29%29+*+H)
are a bit more readable:

{{<katex>}}$$\frac{\partial f}{\partial x} w(x, y) = \frac{w\left(x,y\right)\cdot x\cos\left(d\right)}{d}$$

{{<katex>}}$$\frac{\partial f}{\partial y} w(x, y)  = w\left(x,y\right)\cdot\left(\frac{y\cos\left(d\right)}{d}+\cos\left(y\right)\right)$$

Once we convert this to code, we can adjust our target position using this:

```gdscript
func _wave_gradient(p: Vector3) -> Vector3:
    # in reality x/y are further parameterized by time
	var time = total_time * wave_speed
	var uv = (Math.vec2(p) + time * Vector2(0.5, 0.5)) * wave_size 
	var d = uv.length()

	var w = pow(2.1231, sin(d) + sin((uv.y + 1.0))) * height
	var dx = (uv.x * w * cos(d)) / d
	var dy = w * ((uv.y * cos(d)) / d + cos(uv.y + 1))
	return Vector3(dx, 0, dy).normalized()

func fit_plane(center: Vector3, size: Vector2):
    # ...

    var surface_point = center - _wave_gradient(center)

	# convert to transform
	var rotation_axis = Vector3.UP.cross(normal).normalized()
	var rotation_angle = Vector3.UP.angle_to(normal)
	if rotation_axis.length_squared() < .1:
		rotation_axis = Vector3.RIGHT
	return Transform3D(Basis(rotation_axis.normalized(), rotation_angle), surface_point)
```

If we simply set our object's position to the `surface_point` it will slide
towards a local minima of the wave.

{{<video "basic_slide.webm" >}}

That looks a bit too quick. Multiplying by delta time fixes this:

```gdscript
global_position += (surface_transform.origin - global_position) * Vector3(push_strength*delta, 1, push_strength*delta) 
```

We can add some artistic control by adding a `push_strength` parameter.

```gdscript
func fit_plane(center: Vector3, size: Vector2, strength: float):
    # ...
    var surface_point = center - _wave_gradient(center) * strength
```


{{<video "soft_slide.webm" >}}

Because of the smaller step, we don't keep up with the wave. Because of the
wave changing slope at a given point over time, the object can eventually end
up changing direction. Instead of getting stuck at some local minimum after
encountering one wave, our object looks like it's swaying back and forth.

## Central Differences (Again)

While this is very precise, doing the calculus to get that
gradient takes an extra step of manual work. Each time the
structure of our `_wave` function changes, that new function must
be differentiated. We can simply re-use the finite differences
method from earlier here. The analytic approach could still be
useful for validation. 

The only modification is how we construct the vector to get the
gradient (aka slope) instead of the normal:

```gdscript
var grad = Vector3(dx, 0.0, dz) / step
```

## Swimming

What about objects that aren't _always_ in the water? We can re-use all of what
we've done so far to implement a swimming mechanic. Instead of the model being
a child of the plane, we can have a plane that is the child of a body.


First we detect whether or not we're in the water to turn the influence on or off:

```gdscript
# get swimming position of the parent body
var surface_pos = water.fit_plane(self, Math.vec2(size))
surface_pos.origin -= (global_position - parent.global_position)

# activate swimming mode if we're submerged
if surface_pos.origin.y > global_position.y:
    active = true
    animation.queue_action("swim")

# if the player jumps or otherwise ends up above the surface, we're no longer swimming
if parent.global_position.y - surface_pos.origin.y > deactivate_margin:
    active = false
```

And then apply the influence of the water on the body to `velocity` rather than directly
changing the `position`.

```gdscript
# align to surface
parent.global_position.y = surface_pos.origin.y

# push the player around with the waves
parent.velocity += (surface_pos.origin - parent.global_position) * delta
```

{{<video "bobbing.webm" >}}

This bobbing effect looks neat. After some fine tuning, it could be pretty
good, but there is already a lot of motion applied to the player outside their
control. Another layer of unpredicatability would take away from the fun, so
instead, lets make them stick to the water's surface.

```gdscript
parent.velocity += (surface_pos.origin - parent.global_position) * Vector3(1, 0, 1) * delta
parent.global_position.y = surface_pos.origin.y
```

{{<video "bad_col.webm" >}}

Well, setting the position directly means `move_and_slide` doesn't get the
opportunity to slide the player and leads to them clipping through walls.
Instead, we can _assign_ the y component of velocity so that it puts us exactly
on the surface.

```gdscript
var impulse = (surface_pos.origin - parent.global_position) * Vector3(delta, 1/delta, delta) 
parent.velocity += impulse
parent.velocity.y = impulse.y 
```

{{<video "swim.webm" >}}

## Conclusion

As with any stylized art, it's best to start with a somewhat realistic "ground
truth" and then simplify and improvise. Even cartoonish styles require
attention to detail. The key is choosing _which_ details to draw attention to
and which to minimize or omit. But of course, not having as many performance
concerns as a hyperrealistic render is nice as well.

