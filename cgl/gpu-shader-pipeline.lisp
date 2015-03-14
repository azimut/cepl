(in-package :cgl)

(defun %defpipeline-gfuncs (name args gpipe-args options &optional suppress-compile)
  ;; {TODO} context is now options, need to parse this
  (when args (warn "defpipeline: extra args are not used in pipelines composed of g-functions"))
  (let ((pass-key (gensym "PASS-"))) ;; used as key for memoization
    (assoc-bind ((context :context) (post :post)) (parse-options options)
      (destructuring-bind (stage-pairs gpipe-context)
          (parse-gpipe-args gpipe-args)
        (assert (not (and gpipe-context context)))
        (let ((context (or context gpipe-context))
              (stage-names (mapcar #'cdr stage-pairs)))
          `(progn
             (let-pipeline-vars (,stage-pairs ,pass-key)
               (eval-when (:compile-toplevel :load-toplevel :execute)
                 (update-pipeline-spec
                  (make-pipeline-spec ',name ',stage-names
                                      ',(stages-to-uniform-details stage-pairs
                                                                  pass-key)
                                      ',(or gpipe-context context))))
               (def-pipeline-invalidate ,name)
               (def-pipeline-init ,name ,stage-pairs ,post ,pass-key)
               (def-dispatch-func ,name ,stage-pairs ,context ,pass-key)
               (def-dummy-func ,name ,stage-pairs ,pass-key))
             (defun ,(recompile-name name) ()
               (unless (equalp (slot-value (pipeline-spec ',name)
                                           'uniforms)
                               (stages-to-uniform-details ',stage-pairs))
                 (eval (%defpipeline-gfuncs ',name ',args
                                            ',gpipe-args ',options t))))
             ,(unless suppress-compile `(,(recompile-name name)))))))))

(defmacro let-pipeline-vars ((stage-pairs pass-key) &body body)
  (with-processed-func-specs (mapcar #'cdr stage-pairs)
    (let ((uniform-details
           (mapcar (lambda (x) (make-arg-assigners x pass-key))
                   (expand-equivalent-types unexpanded-uniforms))))
      `(let ((program-id nil)
             ,@(let ((u-lets (mapcan #'first uniform-details)))
                    (mapquote `(,(first %) -1) u-lets)))
         ,@body))))

(defmacro def-pipeline-invalidate (name)
  `(defun ,(invalidate-func-name name) () (setf program-id nil)))

(defun %gl-make-shader-from-varjo (compiled-stage)
  (make-shader (varjo->gl-stage-names (varjo::stage-type compiled-stage))
               (varjo::glsl-code compiled-stage)))

(defmacro def-pipeline-init (name stage-pairs post pass-key)
  (let* ((stage-names (mapcar #'cdr stage-pairs))
         (uniform-details
          (with-processed-func-specs stage-names
            (mapcar (lambda (x) (make-arg-assigners x pass-key))
                    (expand-equivalent-types unexpanded-uniforms)))))
    `(defun ,(init-func-name name) ()
       (let* ((compiled-stages (%varjo-compile-as-pipeline ',stage-pairs))
              (stages-objects (mapcar #'%gl-make-shader-from-varjo
                                      compiled-stages))
              (prog-id (request-program-id-for ',name))
              (image-unit -1))
         (declare (ignorable image-unit))
         (format t ,(format nil "~&; uploading (~a ...)~&" name))
         (link-shaders stages-objects prog-id)
         (mapcar #'%gl:delete-shader stages-objects)
         ,@(let ((u-lets (mapcan #'first uniform-details)))
                (loop for u in u-lets collect (cons 'setf u)))
         (unbind-buffer)
         (force-bind-vao 0)
         (force-use-program 0)
         (setf program-id prog-id)
         ,(when post `(funcall ,post))         
         prog-id))))

(defun stages-to-uniform-details (stage-pairs &optional pass-key)
  (with-processed-func-specs (mapcar #'cdr stage-pairs)
    (mapcar (lambda (x) (make-arg-assigners x pass-key))
            (expand-equivalent-types unexpanded-uniforms))))

(defmacro def-dispatch-func (name stage-pairs context pass-key)
  (with-processed-func-specs (mapcar #'cdr stage-pairs)
    (let* ((uniform-details (mapcar (lambda (x) (make-arg-assigners x pass-key))
                                    (expand-equivalent-types
                                     unexpanded-uniforms)))
           (uniform-names (mapcar #'first unexpanded-uniforms))
           (prim-type (varjo::get-primitive-type-from-context context))
           (u-uploads (mapcar #'second uniform-details)))
      `(defun ,(dispatch-func-name name)
           (stream ,@(when unexpanded-uniforms `(&key ,@uniform-names)))
         (declare (ignorable ,@uniform-names))
         (unless program-id (setf program-id (,(init-func-name name))))
         (use-program program-id)
         ,@u-uploads
         (when stream (draw-expander stream ,prim-type))
         (use-program 0)
         stream))))

(defmacro def-dummy-func (name stage-pairs pass-key)
  (with-processed-func-specs (mapcar #'cdr stage-pairs)
    (let* ((uniform-details (mapcar (lambda (x) (make-arg-assigners x pass-key))
                                    (expand-equivalent-types
                                     unexpanded-uniforms)))
           (uniform-names (mapcar #'first unexpanded-uniforms))
           (u-uploads (mapcar #'second uniform-details)))
      `(defun ,name (stream ,@(when unexpanded-uniforms `(&key ,@uniform-names)))
         (declare (ignorable ,@uniform-names))
         (unless program-id (setf program-id (,(init-func-name name))))
         (use-program program-id)
         ,@u-uploads
         (when stream
           (error "Pipelines do not take a stream directly, the stream must be gmap'd over the pipeline"))
         (use-program 0)
         stream))))


(defmacro draw-expander (stream draw-type)
  "This draws the single stream provided using the currently
   bound program. Please note: It Does Not bind the program so
   this function should only be used from another function which
   is handling the binding."
  `(let ((stream ,stream)
         (draw-type ,draw-type)
         (index-type (vertex-stream-index-type stream)))
     (bind-vao (vertex-stream-vao stream))
     (if (= |*instance-count*| 0)
         (if index-type
             (%gl:draw-elements draw-type
                                (vertex-stream-length stream)
                                (gl::cffi-type-to-gl index-type)
                                (make-pointer 0))
             (%gl:draw-arrays draw-type
                              (vertex-stream-start stream)
                              (vertex-stream-length stream)))
         (if index-type
             (%gl:draw-elements-instanced
              draw-type
              (vertex-stream-length stream)
              (gl::cffi-type-to-gl index-type)
              (make-pointer 0)
              |*instance-count*|)
             (%gl:draw-arrays-instanced
              draw-type
              (vertex-stream-start stream)
              (vertex-stream-length stream)
              |*instance-count*|)))))



;;;--------------------------------------------------------------
;;; ARG ASSIGNERS ;;;
;;;---------------;;;

(let ((cached-data nil)
      (cached-key nil))
  (defun make-arg-assigners (uniform-arg &optional pass-key)
    (if (and pass-key (eq cached-key pass-key))
        (progn
          (print "use cached")
          (return-from make-arg-assigners cached-data))
        (let ((result (%make-arg-assigners uniform-arg)))
          (print "gen")
          (when pass-key
            (setf cached-key pass-key)
            (setf cached-data result))
          result))))

(defun %make-arg-assigners (uniform-arg &aux gen-ids assigners)
  (destructuring-bind ((arg-name &optional expanded-from converter)
                       varjo-type~1) uniform-arg
    (let* ((varjo-type (varjo::type-spec->type varjo-type~1))
           (glsl-name (varjo::safe-glsl-name-string arg-name))
           (struct-arg (varjo::v-typep varjo-type 'varjo::v-user-struct))
           (array-length (when (v-typep varjo-type 'v-array)
                           (apply #'* (v-dimensions varjo-type))))
           (sampler (sampler-typep varjo-type)))
      (loop :for (gid asn multi-gid) :in
         (cond (array-length (make-array-assigners varjo-type glsl-name))
               (struct-arg (make-struct-assigners varjo-type glsl-name))
               (sampler `(,(make-sampler-assigner varjo-type glsl-name nil)))
               (t `(,(make-simple-assigner varjo-type glsl-name nil))))
         :do (if multi-gid
                 (progn (loop for g in gid :do (push g gen-ids))
                        (push asn assigners))
                 (progn (push gid gen-ids) (push asn assigners))))
      (let ((val~ (if expanded-from
                      expanded-from
                      (if (or array-length struct-arg)
                          `(pointer ,arg-name)
                          arg-name))))
        `(,(reverse gen-ids)
           (when ,(or expanded-from arg-name)
             (let ((val ,(cond ((null converter) val~)
                               ((eq (first converter) 'function)
                                `(,(second converter) ,val~))
                               ((eq (first converter) 'lambda)
                                `(labels ((c ,@(rest converter)))
                                   (c ,val~)))
                               (t (error "invalid converter in make-arg-assigners")))))
               ,@(reverse assigners))))))))

(defun make-sampler-assigner (type path &optional (byte-offset 0))
  (declare (ignore byte-offset))
  (let ((id-name (gensym))
        (i-unit (gensym "IMAGE-UNIT")))
    `(((,id-name (gl:get-uniform-location prog-id ,path))
       (,i-unit (incf image-unit)))
      (when (>= ,id-name 0)
        (unless (eq (sampler-type val) ,(type->spec type))
          (error "incorrect texture type passed to shader"))
        ;; (unless ,id-name
        ;;   (error "Texture uniforms must be populated")) ;; [TODO] this wont work here
        (active-texture-num ,i-unit)
        (bind-texture val)
        (uniform-sampler ,id-name ,i-unit))
      t)))

(defun make-simple-assigner (type path &optional (byte-offset 0))
  (let ((id-name (gensym)))
    `((,id-name (gl:get-uniform-location prog-id ,path))
      (when (>= ,id-name 0)
        ,(if byte-offset
             `(,(get-foreign-uniform-function-name (type->spec type))
                ,id-name 1 (cffi:inc-pointer val ,byte-offset))
             `(,(get-uniform-function-name (type->spec type)) ,id-name val)))
      nil)))

(defun make-array-assigners (type path &optional (byte-offset 0))
  (let ((element-type (varjo::v-element-type type))
        (array-length (apply #'* (v-dimensions type))))
    (loop :for i :below array-length :append
       (cond ((varjo::v-typep element-type 'varjo::v-user-struct)
              (make-struct-assigners element-type byte-offset))
             (t (list (make-simple-assigner element-type
                                            (format nil "~a[~a]" path i)
                                            byte-offset))))
       :do (incf byte-offset (gl-type-size element-type)))))

(defun make-struct-assigners (type path &optional (byte-offset 0))
  (loop :for (l-slot-name v-slot-type) :in (varjo::v-slots type)
     :for glsl-name = (varjo::safe-glsl-name-string l-slot-name) :append
     (destructuring-bind (pslot-type array-length . rest) v-slot-type
       (declare (ignore rest))
       (let ((path (format nil "~a.~a" path glsl-name)))
         (prog1
             (cond (array-length (make-array-assigners v-slot-type path
                                                       byte-offset))
                   ((varjo::v-typep pslot-type 'v-user-struct)
                    (make-struct-assigners pslot-type path byte-offset))
                   (t (list (make-simple-assigner pslot-type path
                                                  byte-offset))))
           (incf byte-offset (* (gl-type-size pslot-type)
                                (or array-length 1))))))))

;;;--------------------------------------------------------------
;;; GL HELPERS ;;;
;;;------------;;;

(defun program-attrib-count (program)
  "Returns the number of attributes used by the shader"
  (gl:get-program program :active-attributes))

(defun program-attributes (program)
  "Returns a list of details of the attributes used by
   the program. Each element in the list is a list in the
   format: (attribute-name attribute-type attribute-size)"
  (loop for i from 0 below (program-attrib-count program)
     collect (multiple-value-bind (size type name)
                 (gl:get-active-attrib program i)
               (list name type size))))

(defun program-uniform-count (program)
  "Returns the number of uniforms used by the shader"
  (gl:get-program program :active-uniforms))

(defun program-uniforms (program-id)
  "Returns a list of details of the uniforms used by
   the program. Each element in the list is a list in the
   format: (uniform-name uniform-type uniform-size)"
  (loop for i from 0 below (program-uniform-count program-id)
     collect (multiple-value-bind (size type name)
                 (gl:get-active-uniform program-id i)
               (list name type size))))

(let ((program-cache nil))
  (defun use-program (program-id)
    (unless (eq program-id program-cache)
      (gl:use-program program-id)
      (setf program-cache program-id)))
  (defun force-use-program (program-id)
    (gl:use-program program-id)
    (setf program-cache program-id)))
(setf (documentation 'use-program 'function)
      "Installs a program object as part of current rendering state")

;; [TODO] Expand on this and allow loading on strings/text files for making
;;        shaders
(defun shader-type-from-path (path)
  "This uses the extension to return the type of the shader.
   Currently it only recognises .vert or .frag files"
  (let* ((plen (length path))
         (exten (subseq path (- plen 5) plen)))
    (cond ((equal exten ".vert") :vertex-shader)
          ((equal exten ".frag") :fragment-shader)
          (t (error "Could not extract shader type from shader file extension (must be .vert or .frag)")))))

(defun make-shader
    (shader-type source-string &optional (shader-id (gl:create-shader
                                                     shader-type)))
  "This makes a new opengl shader object by compiling the text
   in the specified file and, unless specified, establishing the
   shader type from the file extension"
  (gl:shader-source shader-id source-string)
  (gl:compile-shader shader-id)
  ;;check for compile errors
  (when (not (gl:get-shader shader-id :compile-status))
    (error "Error compiling ~(~a~): ~%~a~%~%~a"
           shader-type
           (gl:get-shader-info-log shader-id)
           source-string))
  shader-id)

(defun load-shader (file-path
                    &optional (shader-type
                               (shader-type-from-path file-path)))
  (restart-case
      (make-shader (utils:file-to-string file-path) shader-type)
    (reload-recompile-shader () (load-shader file-path
                                             shader-type))))

(defun load-shaders (&rest shader-paths)
  (mapcar #'load-shader shader-paths))

(defun link-shaders (shaders &optional program_id)
  "Links all the shaders provided and returns an opengl program
   object. Will recompile an existing program if ID is provided"
  (let ((program (or program_id (gl:create-program))))
    (unwind-protect
         (progn (loop :for shader :in shaders :do
                   (gl:attach-shader program shader))
                (gl:link-program program)
                ;;check for linking errors
                (if (not (gl:get-program program :link-status))
                    (error (format nil "Error Linking Program~%~a"
                                   (gl:get-program-info-log program)))))
      (loop :for shader :in shaders :do
         (gl:detach-shader program shader)))
    program))