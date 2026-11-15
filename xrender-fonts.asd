;;;; xrender-fonts.asd

(asdf:defsystem #:xrender-fonts
  :serial t
  :description "Fast TrueType/OpenType font rendering for StumpWM using FreeType and XRender glyph sets."
  :version "0.1.0"
  :author "sotanigawa"
  :license "GPLv3+"
  :homepage "https://github.com/sotanigawa/xrender-fonts"
  :depends-on (#:stumpwm #:cffi)
  :components ((:file "package")
               (:file "freetype")
               (:file "xrender-fonts")))
