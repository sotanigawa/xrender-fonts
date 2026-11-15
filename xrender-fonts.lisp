;;;; xrender-fonts.lisp --- StumpWM font backend: FreeType rasterizes each
;;;; glyph once, it is uploaded once into an XRender glyph set, and every
;;;; later draw is a single CompositeGlyphs request.

(in-package #:xrender-fonts)

(defstruct (glyph (:constructor %make-glyph))
  (id 0 :type (unsigned-byte 32))      ; FreeType glyph index, also X glyph id
  (advance 0 :type fixnum)             ; horizontal advance in pixels
  (left 0 :type fixnum)                ; bitmap offset from the pen position
  (top 0 :type fixnum)
  (bitmap nil))                        ; (rows cols) array of 8-bit coverage

(defclass font ()
  ((face :initarg :face :reader font-face)
   (ascent :initarg :ascent :reader %font-ascent)
   (descent :initarg :descent :reader %font-descent)
   (glyphs :initform (make-hash-table) :reader font-glyphs) ; char-code -> glyph
   ;; X side state, valid for one display at a time.
   (display :initform nil :accessor font-display)
   (glyph-set :initform nil :accessor font-glyph-set)
   (uploaded :initform (make-hash-table) :reader font-uploaded)))

(defun load-font (path size &key (index 0) (dpi 96))
  "Load the font file PATH (.ttf, .otf or .ttc) at SIZE points.
INDEX selects a face inside a .ttc collection."
  (let ((face (cffi:with-foreign-object (p :pointer)
                (unless (zerop (ft-new-face (ft-library) (namestring path) index p))
                  (error "Cannot open font ~A (face ~D)" path index))
                (cffi:mem-ref p :pointer))))
    (unless (zerop (ft-set-char-size face 0 (round (* size 64)) dpi dpi))
      (error "Cannot set size ~A for font ~A" size path))
    (let* ((size-rec (cffi:foreign-slot-value face '(:struct ft-face-rec) 'size))
           (metrics (cffi:foreign-slot-pointer size-rec '(:struct ft-size-rec) 'metrics)))
      (flet ((metric (name)
               (cffi:foreign-slot-value metrics '(:struct ft-size-metrics) name)))
        (make-instance 'font
                       :face face
                       :ascent (ceiling (metric 'ascender) 64)
                       :descent (ceiling (- (metric 'descender)) 64))))))

(defun find-glyph (font code)
  "Return the cached glyph for character CODE, rasterizing it on first use."
  (let ((table (font-glyphs font)))
    (or (gethash code table)
        (setf (gethash code table) (rasterize font code)))))

(defun rasterize (font code)
  (let* ((face (font-face font))
         (id (ft-get-char-index face code)))
    (unless (zerop (ft-load-glyph face id +ft-load-render+))
      ;; Unloadable glyph: draw nothing, take no space.
      (return-from rasterize (%make-glyph :id id)))
    (let* ((slot (cffi:foreign-slot-value face '(:struct ft-face-rec) 'glyph))
           (bm (cffi:foreign-slot-pointer slot '(:struct ft-glyph-slot-rec) 'bitmap))
           (gray (= (cffi:foreign-slot-value bm '(:struct ft-bitmap) 'pixel-mode)
                    +ft-pixel-mode-gray+))
           (rows (if gray (cffi:foreign-slot-value bm '(:struct ft-bitmap) 'rows) 0))
           (cols (if gray (cffi:foreign-slot-value bm '(:struct ft-bitmap) 'width) 0))
           (pitch (cffi:foreign-slot-value bm '(:struct ft-bitmap) 'pitch))
           (buffer (cffi:foreign-slot-value bm '(:struct ft-bitmap) 'buffer))
           (data (make-array (list (max rows 1) (max cols 1))
                             :element-type '(unsigned-byte 8) :initial-element 0)))
      (dotimes (y rows)
        (dotimes (x cols)
          (setf (aref data y x) (cffi:mem-aref buffer :uint8 (+ (* y pitch) x)))))
      (%make-glyph
       :id id
       :advance (round (cffi:foreign-slot-value slot '(:struct ft-glyph-slot-rec) 'advance-x) 64)
       :left (cffi:foreign-slot-value slot '(:struct ft-glyph-slot-rec) 'bitmap-left)
       :top (cffi:foreign-slot-value slot '(:struct ft-glyph-slot-rec) 'bitmap-top)
       :bitmap data))))

;;; X side helpers

(defun a8-format (display)
  (or (getf (xlib:display-plist display) 'a8-format)
      (setf (getf (xlib:display-plist display) 'a8-format)
            (first (xlib:find-matching-picture-formats
                    display :depth 8 :alpha 8 :red 0 :green 0 :blue 0)))))

;; CLX asks the server (a blocking round trip) every time DRAWABLE-DEPTH or
;; DRAWABLE-ROOT is called, so everything derived from them is cached: on the
;; drawable object itself (no server resources, so nothing leaks when StumpWM
;; recreates a pixmap) and per display and depth.

(defun drawable-info (drawable)
  "Return (depth format root) for DRAWABLE."
  (or (getf (xlib:drawable-plist drawable) 'info)
      (setf (getf (xlib:drawable-plist drawable) 'info)
            (let* ((display (xlib:drawable-display drawable))
                   (depth (xlib:drawable-depth drawable))
                   (root (xlib:drawable-root drawable)))
              (list depth
                    (if (= depth (xlib:drawable-depth root))
                        (xlib:find-window-picture-format root)
                        (first (xlib:find-matching-picture-formats display :depth depth)))
                    root)))))

(defun pen (drawable)
  "A 1x1 repeating pixmap and picture used as the text colour source."
  (destructuring-bind (depth format root) (drawable-info drawable)
    (let ((display (xlib:drawable-display drawable)))
      (or (cdr (assoc depth (getf (xlib:display-plist display) 'pens)))
          (let* ((pixmap (xlib:create-pixmap :drawable root :depth depth :width 1 :height 1))
                 (pen (cons pixmap (xlib:render-create-picture pixmap :format format
                                                                      :repeat :on))))
            (push (cons depth pen) (getf (xlib:display-plist display) 'pens))
            pen)))))

(defun ensure-glyph-set (font display)
  (unless (eq (font-display font) display)
    (setf (font-display font) display
          (font-glyph-set font) (xlib:render-create-glyph-set (a8-format display)))
    (clrhash (font-uploaded font)))
  (font-glyph-set font))

(defun upload (font glyph-set glyph)
  (let ((id (glyph-id glyph)))
    (unless (gethash id (font-uploaded font))
      (xlib:render-add-glyph glyph-set id
                             :x-origin (- (glyph-left glyph))
                             :y-origin (glyph-top glyph)
                             :x-advance (glyph-advance glyph)
                             :y-advance 0
                             :data (or (glyph-bitmap glyph)
                                       (make-array '(1 1) :element-type '(unsigned-byte 8)
                                                          :initial-element 0)))
      (setf (gethash id (font-uploaded font)) t))))

;;; StumpWM font protocol

(defmethod font-exists-p ((font font)) t)

(defmethod open-font (display (font font))
  (declare (ignore display))
  font)

(defmethod close-font ((font font))
  ;; StumpWM may close a font object it is about to reuse, so only drop the
  ;; X side state; it is rebuilt lazily on the next draw.
  (when (font-glyph-set font)
    (ignore-errors (xlib:render-free-glyph-set (font-glyph-set font))))
  (setf (font-display font) nil
        (font-glyph-set font) nil)
  (clrhash (font-uploaded font))
  t)

(defmethod font-ascent ((font font)) (%font-ascent font))
(defmethod font-descent ((font font)) (%font-descent font))
(defmethod font-height ((font font)) (+ (%font-ascent font) (%font-descent font)))

(defmethod text-line-width ((font font) text &rest keys &key (start 0) end translate)
  (declare (ignore keys translate))
  (loop for i from start below (or end (length text))
        sum (glyph-advance (find-glyph font (char-code (char text i))))))

(defmethod draw-image-glyphs (drawable gcontext (font font) x y text
                              &rest keys &key (start 0) end translate width size)
  (declare (ignore keys translate width size))
  (let* ((end (or end (length text)))
         (count (- end start)))
    (when (plusp count)
      (let* ((display (xlib:drawable-display drawable))
             (glyph-set (ensure-glyph-set font display))
             (ids (make-array count :element-type '(unsigned-byte 32)))
             (width 0))
        (loop for i from start below end
              for j from 0
              for glyph = (find-glyph font (char-code (char text i)))
              do (upload font glyph-set glyph)
                 (setf (aref ids j) (glyph-id glyph))
                 (incf width (glyph-advance glyph)))
        (destructuring-bind (pen-pixmap . pen-picture) (pen drawable)
          ;; Text colour = gcontext foreground.
          (xlib:draw-point pen-pixmap gcontext 0 0)
          ;; Image-text semantics: paint the background box first.
          (let ((fg (xlib:gcontext-foreground gcontext)))
            (setf (xlib:gcontext-foreground gcontext) (xlib:gcontext-background gcontext))
            (xlib:draw-rectangle drawable gcontext x (- y (%font-ascent font))
                                 width (font-height font) t)
            (setf (xlib:gcontext-foreground gcontext) fg))
          ;; The destination picture is created per call: pixmaps are
          ;; recreated by StumpWM on resize, and a cached picture would keep
          ;; freed pixmaps alive in the server.
          (let ((dest (xlib:render-create-picture drawable
                                                  :format (second (drawable-info drawable)))))
            (xlib:render-composite-glyphs dest glyph-set pen-picture x y ids
                                          :op :over :mask-format (a8-format display))
            (xlib:render-free-picture dest)))))))
