;;;; bench.lisp --- measure text drawing speed of a StumpWM font object.
;;;;
;;;; Not part of the system.  Load it inside a running StumpWM
;;;; (e.g. from SLY/SLIME, or C-t : (load "/path/to/bench.lisp")) and call
;;;;   (xrender-fonts-bench:run some-font)
;;;; with any font object StumpWM accepts (xrender-fonts, sdl-fonts, ...).

(defpackage #:xrender-fonts-bench
  (:use #:cl)
  (:export #:run))

(in-package #:xrender-fonts-bench)

(defun run (font &key (n 200)
                   (text "[1] emacs | firefox | 2026-11-15 (日) 15:54:07 | CPU 12%"))
  "Draw TEXT N times into an off-screen pixmap with FONT.
Returns milliseconds per draw (including the server's work)."
  (let* ((display stumpwm:*display*)
         (root (xlib:screen-root (first (xlib:display-roots display))))
         (pixmap (xlib:create-pixmap :drawable root :width 1200 :height 50
                                     :depth (xlib:drawable-depth root)))
         (gc (xlib:create-gcontext :drawable pixmap :foreground 0 :background 0)))
    (unwind-protect
         (flet ((draw ()
                  (stumpwm::draw-image-glyphs pixmap gc font 0 30 text)
                  (stumpwm::text-line-width font text)))
           (draw)                       ; warm up caches
           (xlib:display-finish-output display)
           (let ((start (get-internal-real-time)))
             (dotimes (i n) (draw))
             (xlib:display-finish-output display)
             (/ (* 1000.0 (- (get-internal-real-time) start))
                internal-time-units-per-second n)))
      (xlib:free-gcontext gc)
      (xlib:free-pixmap pixmap))))
