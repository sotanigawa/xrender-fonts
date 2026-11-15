;;;; package.lisp

(defpackage #:xrender-fonts
  (:use #:cl)
  (:import-from #:stumpwm
                #:font-exists-p
                #:open-font
                #:close-font
                #:font-ascent
                #:font-descent
                #:font-height
                #:text-line-width
                #:draw-image-glyphs)
  (:export #:load-font))
