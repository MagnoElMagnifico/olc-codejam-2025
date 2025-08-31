# OLC Codejam 2025

Our submission to the [OLC CodeJam 2025], using the [Odin Programming Language].
This project is based on the [Web Odin Template] from Karl Zylinski (which he
explains in [this video]), using [Raylib].

The theme for this Jam was **shapes**.

# Building

Run the specific files for your platform:

- Windows Desktop: `build_desktop.bat`
- Linux Desktop: `build_desktop.sh`
- Windows Web: `build_web.bat` (you need [Emscripten] installed, add location to the script)
- Linux Web: `build_web.sh` (you need [Emscripten] installed, add location to the script)

Note that for desktop, essentially just run the Odin Compiler:

```bash
odin build src/main_desktop -out:synth_shapes.exe

```

The executable needs to be next to the `assets` directory, so if you want to
distribute the binaries, remember to copy it as well (this is what the script
does).

Tested with the Odin Compiler version `dev-2025-08-nightly` and Emscripten
`4.0.13`.

# How to use

The idea of this application is to create music using regular shapes.
The dot moving through the figure is the _beat_, and each time it reaches a
vertex, a sound will be played. Currently there are 3 instruments.

Also, if a figure is smaller, the beat will have to travel less distance, which
means a faster pace.

In _select mode_ (press `1` on your keyboard or the `S` button on the UI) you
can:

-   Left click and drag to create new figures (note that if the figure is too
    small, it will be deleted). You can use the UI on the left to configure what
    properties they will have.
-   Left click on the circle on the center of the figure to select it. With the
    UI on the right, you will be able to modify its properties: point speed,
    music notes, the counter, number of sides of the figure, etc.
-   You can resize the figure by moving the small circle on one of the figure's
    vertices. This makes the beat faster or slower.
-   You can synchronize the beat with the rest of the sounds by clicking on the
    figure's sides. To reset the current cicle, use the button `Synch beats`.
-   Each figure will have a counter. When the beats completes one cicle, the
    counter gets decreased by one. When the counter is 0, no more sounds will be
    played.
-   Use `Ctrl-D` to duplicate the selection.
-   Holding `Shift`, you can select more, or use right click and drag to select
    figures in a rectangular fashion.
-   Use `Delete` or `Backspace` to delete the figures currently selected.
-   Left click elsewhere or press `Esc` to cancel the current selection.

The _link mode_ (number `2` or the `L` button) will allow you to create links
between the different figures to create longer sequences. When a figure's
counter reaches 0, the linked figure will start playing.

-   To create a new link, left click to select the two figures.
-   You can only link to one figure, so re-linking a figure will overwrite the
    previous.
-   Double click a figure to remove its link (essentially, a link to itself).


Anytime, you can use `Space` to pause the simulation and the mouse wheel to move
the camera around.

# Useful links

- [Odin Overview](https://odin-lang.org/docs/overview/)
- [Odin Demo](https://github.com/odin-lang/Odin/blob/master/examples/demo/demo.odin)
- [Odin Package Reference](https://pkg.odin-lang.org/)
- [Raylib Examples](https://www.raylib.com/examples.html)
- [Raylib Cheatsheet](https://www.raylib.com/cheatsheet/cheatsheet.html)

[Emscripten]: https://emscripten.org/
[OLC CodeJam 2025]: https://itch.io/jam/olc-codejam-2025
[Odin Programming Language]: https://odin-lang.org/
[Web Odin Template]: https://github.com/karl-zylinski/odin-raylib-web
[this video]: https://youtu.be/WhRIjmHS-Og
[Raylib]: https://www.raylib.com/
