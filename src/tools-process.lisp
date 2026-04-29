(in-package #:sbcl-agent)

(register-compatibility-backend-profile :host-process-sync
                                        "Synchronous host process sandbox"
                                        :substrate-kind :sandbox-worker-process
                                        :isolation-class :bounded-host-process
                                        :control-plane-kind :none
                                        :display-bridge-kind :none
                                        :filesystem-model :sandbox-profile
                                        :network-model :sandbox-profile
                                        :persistence-model :ephemeral
                                        :host-process-p t)

(register-compatibility-backend-profile :host-process-detached
                                        "Detached host process sandbox"
                                        :substrate-kind :sandbox-worker-process
                                        :isolation-class :bounded-host-process
                                        :control-plane-kind :process-token
                                        :display-bridge-kind :none
                                        :filesystem-model :sandbox-profile
                                        :network-model :sandbox-profile
                                        :persistence-model :process-lifetime
                                        :host-process-p t)

(register-compatibility-backend-profile :desktop-app-bridge
                                        "Desktop app bridge sandbox"
                                        :substrate-kind :desktop-bridge-session
                                        :isolation-class :bridged-host-process
                                        :control-plane-kind :desktop-session
                                        :display-bridge-kind :desktop-window
                                        :filesystem-model :manifest-scoped-workspace
                                        :network-model :manifest-policy
                                        :persistence-model :session-runtime
                                        :host-process-p t)

(register-compatibility-backend-profile :managed-desktop-surface
                                        "Managed desktop surface runtime"
                                        :substrate-kind :governed-desktop-surface
                                        :isolation-class :managed-runtime-surface
                                        :control-plane-kind :desktop-session
                                        :display-bridge-kind :desktop-window
                                        :filesystem-model :virtual-surface
                                        :network-model :none
                                        :persistence-model :session-runtime
                                        :host-process-p nil)

(defun tool-proc-run (session &key argv)
  (declare (ignore session argv))
  (error ":proc/run must execute through the sandbox isolation layer"))

(defun tool-proc-spawn (session &key argv)
  (declare (ignore session argv))
  (error ":proc/spawn must execute through the compatibility isolation layer"))

(register-tool :proc/run
               "Run a local process and capture stdout, stderr, and exit code."
               :process-run
               #'tool-proc-run
               :isolation-profile :process-run
               :compatibility-kind :host-process
               :backend-profile-id :host-process-sync)

(register-tool :proc/spawn
               "Spawn a local process as a governed compatibility execution."
               :process-run
               #'tool-proc-spawn
               :isolation-profile :process-run
               :compatibility-kind :host-process
               :backend-profile-id :host-process-detached)

(register-compatibility-app "linux.echo"
                            "Demo Linux app manifest that executes /bin/echo as a governed app."
                            "/bin/echo"
                            :backend-profile-id :host-process-sync
                            :policy-id :linux-app-launch
                            :filesystem-scope-kind :none
                            :network-policy :none
                            :workspace-write-p nil
                            :display-surface-kind :headless
                            :launch-tool-id :proc/run)

(register-compatibility-app "linux.sleep"
                            "Demo Linux app manifest that executes /bin/sleep as a governed app."
                            "/bin/sleep"
                            :backend-profile-id :host-process-detached
                            :policy-id :linux-app-launch
                            :filesystem-scope-kind :none
                            :network-policy :none
                            :workspace-write-p nil
                            :display-surface-kind :headless
                            :launch-tool-id :proc/spawn)

(register-compatibility-app "linux.vscode"
                            "Visual Studio Code Linux app manifest."
                            "code"
                            :backend-profile-id :desktop-app-bridge
                            :policy-id :linux-ide-launch
                            :filesystem-scope-kind :session-workspace
                            :network-policy :client
                            :workspace-write-p t
                            :display-surface-kind :desktop-window
                            :launch-tool-id :proc/spawn)

(register-compatibility-app "linux.intent-demo"
                            "Managed IntentOS desktop surface demo app."
                            "managed://intent-demo"
                            :backend-profile-id :managed-desktop-surface
                            :policy-id :linux-app-launch
                            :filesystem-scope-kind :none
                            :network-policy :none
                            :workspace-write-p nil
                            :display-surface-kind :desktop-window
                            :launch-tool-id :proc/spawn)
