;;;; freetype.lisp --- minimal FreeType 2 bindings (only what this module needs)

(in-package #:xrender-fonts)

(cffi:define-foreign-library libfreetype
  (:unix (:or "libfreetype.so.6" "libfreetype.so"))
  (t (:default "libfreetype")))

(cffi:use-foreign-library libfreetype)

;; Struct layouts follow freetype.h.  Only the leading fields up to the ones
;; we read are required, but they must be exact.

(cffi:defcstruct ft-generic
  (data :pointer)
  (finalizer :pointer))

(cffi:defcstruct ft-bbox
  (x-min :long) (y-min :long) (x-max :long) (y-max :long))

(cffi:defcstruct ft-face-rec
  (num-faces :long)
  (face-index :long)
  (face-flags :long)
  (style-flags :long)
  (num-glyphs :long)
  (family-name :pointer)
  (style-name :pointer)
  (num-fixed-sizes :int)
  (available-sizes :pointer)
  (num-charmaps :int)
  (charmaps :pointer)
  (generic (:struct ft-generic))
  (bbox (:struct ft-bbox))
  (units-per-em :ushort)
  (ascender :short)
  (descender :short)
  (height :short)
  (max-advance-width :short)
  (max-advance-height :short)
  (underline-position :short)
  (underline-thickness :short)
  (glyph :pointer)
  (size :pointer))

(cffi:defcstruct ft-size-metrics
  (x-ppem :ushort) (y-ppem :ushort)
  (x-scale :long) (y-scale :long)
  (ascender :long) (descender :long)
  (height :long) (max-advance :long))

(cffi:defcstruct ft-size-rec
  (face :pointer)
  (generic (:struct ft-generic))
  (metrics (:struct ft-size-metrics)))

(cffi:defcstruct ft-glyph-metrics
  (width :long) (height :long)
  (hori-bearing-x :long) (hori-bearing-y :long) (hori-advance :long)
  (vert-bearing-x :long) (vert-bearing-y :long) (vert-advance :long))

(cffi:defcstruct ft-bitmap
  (rows :uint)
  (width :uint)
  (pitch :int)
  (buffer :pointer)
  (num-grays :ushort)
  (pixel-mode :uchar)
  (palette-mode :uchar)
  (palette :pointer))

(cffi:defcstruct ft-glyph-slot-rec
  (library :pointer)
  (face :pointer)
  (next :pointer)
  (glyph-index :uint)
  (generic (:struct ft-generic))
  (metrics (:struct ft-glyph-metrics))
  (linear-hori-advance :long)
  (linear-vert-advance :long)
  (advance-x :long)
  (advance-y :long)
  (format :uint)
  (bitmap (:struct ft-bitmap))
  (bitmap-left :int)
  (bitmap-top :int))

(cffi:defcfun ("FT_Init_FreeType" ft-init-freetype) :int (library :pointer))
(cffi:defcfun ("FT_New_Face" ft-new-face) :int
  (library :pointer) (path :string) (index :long) (face :pointer))
(cffi:defcfun ("FT_Set_Char_Size" ft-set-char-size) :int
  (face :pointer) (width :long) (height :long) (hres :uint) (vres :uint))
(cffi:defcfun ("FT_Get_Char_Index" ft-get-char-index) :uint
  (face :pointer) (charcode :ulong))
(cffi:defcfun ("FT_Load_Glyph" ft-load-glyph) :int
  (face :pointer) (glyph-index :uint) (flags :int32))

(defconstant +ft-load-render+ 4)
(defconstant +ft-pixel-mode-gray+ 2)

(defvar *ft-library* nil)

(defun ft-library ()
  (or *ft-library*
      (cffi:with-foreign-object (lib :pointer)
        (unless (zerop (ft-init-freetype lib))
          (error "FT_Init_FreeType failed"))
        (setf *ft-library* (cffi:mem-ref lib :pointer)))))
