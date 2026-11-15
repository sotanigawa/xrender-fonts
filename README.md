# xrender-fonts

Fast anti-aliased TrueType/OpenType fonts for [StumpWM](https://stumpwm.github.io/).

Each glyph is rasterized once with FreeType and uploaded once into an
XRender glyph set on the X server. After that, drawing a string is a single
`CompositeGlyphs` request containing glyph ids. No per-draw rasterization,
no image upload, and no blocking round trips to the server.

In a benchmark on Xvfb drawing a typical mode-line string
(`bench.lisp`, Noto Sans CJK JP 14pt), this module took about 0.012 ms per
draw, compared with about 0.12 ms for `sdl-fonts`. That is roughly 10x
faster. Your numbers will vary; use `bench.lisp` to measure on your machine.

## Requirements

- StumpWM
- [CFFI](https://cffi.common-lisp.dev/) (e.g. `(ql:quickload :cffi)`)
- FreeType 2 (`libfreetype.so.6`; installed on almost every Linux desktop)
- An X server with the RENDER extension (any modern one)

## Installation

Clone this repository into your StumpWM module directory
(by default `~/.stumpwm.d/modules/`):

```sh
git clone https://github.com/sotanigawa/xrender-fonts ~/.stumpwm.d/modules/xrender-fonts
```

## Usage

In `~/.stumpwm.d/init.lisp`:

```lisp
(load-module "xrender-fonts")
(set-font (xrender-fonts:load-font
           "/usr/share/fonts/noto/NotoSans-Regular.ttf" 11))
```

`load-font path size &key (index 0) (dpi 96)`

- `path`: a `.ttf`, `.otf` or `.ttc` file.
- `size`: size in points, converted to pixels using `dpi`.
- `index`: face inside a `.ttc` collection. List them with
  `fc-query -f '%{index}: %{family[0]}\n' FILE`.
  In `NotoSansCJK-*.ttc`, index 0 is Noto Sans CJK JP.

There is no font fallback, so pick a font that covers every script you
need. For Japanese, Chinese or Korean, use Noto Sans CJK, e.g.
`(xrender-fonts:load-font "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc" 11)`.

## Limitations

Kept deliberately small. It does **not** do:

- fallback fonts (characters missing from the font are drawn as the font's
  "missing glyph" box)
- complex text shaping (ligatures, Arabic, Indic scripts); characters are
  placed one after another
- kerning, subpixel (LCD) rendering, or hinting options
- color emoji

Latin, Japanese, Chinese and Korean text render correctly.

## Measuring

`bench.lisp` is not loaded by the module. Load it in a running StumpWM and
compare any two font objects:

```lisp
(load "~/.stumpwm.d/modules/xrender-fonts/bench.lisp")
(xrender-fonts-bench:run (xrender-fonts:load-font "/path/to/font.ttc" 11))
;; => milliseconds per draw
```

## License

GPLv3 or later. See `LICENSE`.
