(in-package :cepl)

(defun+ repl (&optional (width 320) (height 240)
               #+darwin (gl-version 4.1)
               #-darwin gl-version)
  "Initialize CEPL and open a window. If the gl-version argument is nil then
   the default for the OS will be used."
  (initialize-cepl :gl-version gl-version)
  (if (uiop:getenv "APPDIR")
      (cepl.context::legacy-add-surface (cepl-context) "CEPL" width height t t
                                        nil nil t gl-version)
      (cepl.context::legacy-add-surface (cepl-context) "CEPL" width height nil t
                                        nil nil t gl-version))
  (format t "~%-----------------~%    CEPL-REPL    ~%-----------------~%")
  (cls))

(defun+ initialize-cepl (&key gl-version host-init-flags)
  (when (uninitialized-p)
    (let ((contexts
           (bt:with-lock-held (cepl.context::*contexts-lock*)
             (copy-list cepl.context::*contexts*))))
      ;;
      ;; Initialize Host
      (unless cepl.host::*current-host*
        (apply #'cepl.host::initialize host-init-flags))
      ;;
      ;; Initalized the already created CEPL contexts
      (loop :for context :in contexts :do
         (cepl.context::patch-uninitialized-context-with-version context gl-version))
      ;;
      ;; Inform the world that CEPL is live
      (cepl.lifecycle::change-state :active)
      t)))

(defun+ quit () (cepl.lifecycle::change-state :shutting-down))

(defun+ register-event-listener (function)
  "Register a function to be called on every event.
   The function must take 1 argument, which will be the event."
  (cepl.host::register-event-listener function))

(defn-inline step-host (&optional (context cepl-context (cepl-context)))
    cepl-context
  (%with-cepl-context-slots (current-surface) context
    (cepl.host::host-step current-surface))
  context)

(defn-inline swap (&optional (context cepl-context (cepl-context)))
    cepl-context
  (%with-cepl-context-slots (current-surface) context
    (cepl.host::host-swap current-surface))
  context)

(defn cls () fbo
  (%with-cepl-context-slots (default-framebuffer) (cepl-context)
    (with-fbo-bound (default-framebuffer :target :framebuffer
                      :with-viewport nil
                      :with-blending nil)
      (clear) (swap)
      (clear) (swap))
    default-framebuffer))

(defun cepl-describe (name &optional (stream *standard-output*))
  (vari:vari-describe name stream))

(in-package :cepl)

(docs:define-docs
  (defun repl
      "
This function is a legacy item at this stage, but is still here as it feels
nice.

It calls #'initialize-cepl to make a resizable window and prints out a message
in the repl.
")

  (defun initialize-cepl
      "
This is how we initialize CEPL. It is important to do this before using any api
that touches the gpu.

When you call this it does a few things:
- Asks the host to initialize itself
- Asks the host for an opengl context and window
- Wraps the gl-context in CEPL's own context object
- Sets up some internals systems

And finally returns t.

CEPL is now ready to use.
")

  (defun quit
      "
Call this to shutdown CEPL.

As well as its own internal work, CEPL will ask the host to shut itself down.
")

  (defun step-host
      "
Call this to ask the host update its own internals.

This description is a bit nebulous as cepl doesnt impose what the host should do
when this call is made; however it is usual to call #'step-host every tick of
a main-loop and so often hosts will use this to do per-tick jobs like polling
for input events.
")

  (defun swap
      "
Call this ask the host to swap the buffers of the default framebuffer.

We usually do this when we have finished drawing a given frame.
")

  (defun cls
      "
CLS is here as it reminds me of qbasic and that makes me happy.

It calls #'clear and #'swap twice so dont use this in your actually rendering
code. It can be handy though if you want to clear the screen from the repl.
"))
