(in-package :cepl.context)

;; We couldnt have this in cepl-context as it required a bunch of stuff
;; from textures & samplers

(defn set-sampler-bound ((ctx cepl-context)
                         (sampler sampler)
                         (tex-unit tex-unit))
    (values)
  (declare (optimize (speed 3) (safety 0) (debug 0) (compilation-speed 0))
           (inline %sampler-texture)
           (profile t))
  (%with-cepl-context-slots (array-of-bound-samplers) ctx
    (when (not (eq sampler (aref array-of-bound-samplers tex-unit)))
      (let ((texture (%sampler-texture sampler)))
        (active-texture-num tex-unit)
        (%gl:bind-texture (texture-cache-id texture) (texture-id texture))
        (if cepl.samplers::*samplers-available*
            (%gl:bind-sampler tex-unit (%sampler-id sampler))
            (cepl.textures::fallback-sampler-set sampler))
        (setf (aref array-of-bound-samplers tex-unit) sampler)
        (when (%cepl.types::%sampler-imagine sampler)
          (ecase (cepl:image-format->lisp-type
                  (cepl.textures:texture-element-type texture))
            ;; RGBA8
            (:UINT8-VEC4
             (if (eq ::TEXTURE-3D (cepl.textures:texture-type texture))
                 ;; TODO: 3D write textures, for atomic write
                 (%gl:bind-image-texture tex-unit
                                         (texture-id texture)
                                         0
                                         t
                                         0
                                         :write-only ;; hard to tell which one default...
                                         (texture-image-format texture))
                 (%gl:bind-image-texture tex-unit
                                         (texture-id texture)
                                         0
                                         t
                                         0
                                         :read-write ;; hard to tell which one default...
                                         (texture-image-format texture))))
            ;; RGBA32F
            (:VEC4
             (%gl:bind-image-texture tex-unit
                                     (texture-id texture)
                                     0
                                     t
                                     0
                                     :write-only ;; hard to tell which one default...
                                     (texture-image-format texture)))
            (:HALF-VEC4 ; rgba16f
             (%gl:bind-image-texture tex-unit
                                     (texture-id texture)
                                     0
                                     t
                                     0
                                     :write-only ;; hard to tell which one default...
                                     (texture-image-format texture)))))))
    (values)))

(defn force-sampler-bound ((ctx cepl-context)
                           (sampler sampler)
                           (tex-unit tex-unit))
    (values)
  (declare (optimize (speed 3) (safety 0) (debug 0) (compilation-speed 0))
           (inline %sampler-texture)
           (profile t))
  (%with-cepl-context-slots (array-of-bound-samplers) ctx
    (let ((texture (%sampler-texture sampler)))
      (active-texture-num tex-unit)
      (%gl:bind-texture (texture-cache-id texture) (texture-id texture))
      (if cepl.samplers::*samplers-available*
          (%gl:bind-sampler tex-unit (%sampler-id sampler))
          (cepl.textures::fallback-sampler-set sampler))
      (setf (aref array-of-bound-samplers tex-unit) sampler))
    (values)))
