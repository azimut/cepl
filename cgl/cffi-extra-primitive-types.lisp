(in-package :cffi)

;; {TODO} need to add info for autowrap

(define-foreign-type cgl-byte () 
  ()
  (:actual-type :char)
  (:simple-parser :byte))

(define-foreign-type cgl-ubyte () 
  ()
  (:actual-type :uchar)
  (:simple-parser :ubyte))

(defmacro make-new-types ()
  (labels ((get-lisp-type (f-type)
             (case f-type
               (bool 'boolean)
               (:int 'integer)
               (:uint 'integer)
               (:double 'float)
               (:float 'single-float)
               (:byte 'fixnum)
               (:ubyte 'fixnum)
               (t (error "How is there a cffi type with components of ~a" f-type)))))
    (let* ((new-user-types '((:vec2 2 :float)
                             (:vec3 3 :float)
                             (:vec4 4 :float)
                             (:ivec2 2 :int)
                             (:ivec3 3 :int)
                             (:ivec4 4 :int)
                             (:uvec2 2 :uint)
                             (:uvec3 3 :uint)
                             (:uvec4 4 :uint)
                             (:mat2 4 :float)
                             (:mat3 9 :float)
                             (:mat4 16 :float)
                             (:mat2x2 4 :float)
                             (:mat2x3 6 :float)
                             (:mat2x4 8 :float)
                             (:mat3x2 6 :float)
                             (:mat3x3 9 :float)
                             (:mat3x4 12 :float)
                             (:mat4x2 8 :float)
                             (:mat4x3 12 :float)
                             (:mat4x4 16 :float)
                             (:ubyte-vec2 2 :ubyte)
                             (:ubyte-vec3 3 :ubyte)
                             (:ubyte-vec4 4 :ubyte)
                             (:byte-vec2 2 :byte)
                             (:byte-vec3 3 :byte)
                             (:byte-vec4 4 :byte))))
      `(progn 
         ,@(loop :for (type len comp-type) :in (append new-user-types)
              :collect
              (let* ((name (utils:symb 'cgl- type))
                     (type-name (utils:symb name '-type))) 
                `(progn
                   (cffi:defcstruct ,name (components ,comp-type :count ,len))
                   (define-foreign-type ,type-name () 
                     ()
                     (:actual-type :struct ,name)
                     (:simple-parser ,type))
                   (defmethod translate-from-foreign (ptr (type ,type-name))
                     (make-array ,len :element-type ',(get-lisp-type comp-type)
                                 :initial-contents
                                 (list ,@(loop :for j :below len :collect 
                                            `(mem-aref ptr ,comp-type ,j)))))
                   (defmethod translate-into-foreign-memory
                       (value (type ,type-name) pointer)
                     ,@(loop :for j :below len :collect 
                          `(setf (mem-aref pointer ,comp-type ,j) (aref value ,j))))
                   ,(when (< len 5)
                          (let ((components (utils:kwd (subseq "RGBA" 0 len))))
                            (when (cgl::valid-pixel-format-p components comp-type t nil)
                              `(defmethod cgl::pixel-format-of ((comp-type (eql ,type)))
                                 (cgl::pixel-format ,components ',comp-type)))))
                   )))))))
(make-new-types)

;; Extra functions, these probably need to live somewhere else
(defcfun (%memcpy "memcpy") :pointer
  (destination-pointer :pointer)
  (source-pointer :pointer)
  (byte-length :long))

(export '(%memcpy))
