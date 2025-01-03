+++
title = "Avoid tmux Nesting with a Simple iTerm2 Trick"
date = "2025-01-02T23:01:52+08:00"
#dateFormat = "2006-01-02" # This value can be configured for per-post date formatting
author = "Harrison Zhu"
authorTwitter = "" #do not include @
cover = ""
tags = ["iterm2", "tmux"]
keywords = ["tmux", "iTerm2", "nested", "automation"]
description = "A guide to avoiding nested tmux sessions by using iTerm2 profiles and simple automations for seamless local and remote workflows."
showFullContent = false
readingTime = 600
hideComments = false
license= "CC BY-ND 4.0"
+++

## 1. The Confusion: Using Tmux Locally **and** Remotely

Picture this: you’ve discovered **tmux**, the awesome terminal multiplexer that gives you persistent sessions, split panes, and an easy way to reattach after disconnections. You fall in love. But then you do this:

1. **Locally** on your Mac, you start tmux in iTerm2—maybe you attach automatically to a session whenever you open a new terminal.
2. You **SSH** to a remote server where, guess what, **tmux** is also running! You attach to that session too…

Suddenly, you’re **nesting tmux** inside tmux. Now you have:

- **Conflicting keybindings**: You press Ctrl+A (or Ctrl+B) but you’re never quite sure if it’s the local tmux or the remote tmux responding.  
- **Mouse weirdness**: Toggling mouse support in your local tmux can prevent mouse events from reaching the remote tmux (pane resizing, scrolling, etc.).  
- **General confusion**: Which status bar belongs to which tmux? Are you splitting local panes or remote panes? Am I resizing the remote or local window?

This can turn the magic of tmux into a headache. Thankfully, there’s a simple trick—using multiple iTerm2 **profiles** plus a few automations—so you can run tmux locally **and** remotely without going crazy.

---

## 2. What You’ll Achieve

By following this guide, you’ll configure your iTerm2 and tmux setup to work seamlessly together, achieving the following:
* Local Automation: When you open a new tab in iTerm2, it will automatically attach to your local tmux session—no extra commands needed.
* Remote Smoothness: When you try to SSH to a remote server from this session, a new tab will automatically open, connect to the remote server, and prevent any local tmux nesting.
* Effortless Cleanup: Once you log out of the SSH session, the tab will automatically close, keeping your terminal clean and clutter-free.

This setup creates a natural, intuitive workflow for managing both local and remote tasks, avoiding the frustrations of nested tmux sessions and ensuring a smooth experience throughout.

---

## 3. Auto-Starting Local tmux in iTerm2

### 3.1 Create a Default Profile

1. In **iTerm2 → Preferences → Profiles**, pick your default profile (or create a new one) and set **Command** to something like:
   ```
   /usr/local/bin/tmux new-session -A -s mylocal
   ```
   Adjust the path as necessary (eg. `/opt/homebrew/bin/tmux`). The `-A -s mylocal` means “attach to session `mylocal` if it exists, otherwise create it.”

2. Now, whenever you open a new iTerm2 tab/window with this **Default** profile, you automatically attach a **local** tmux session. If it’s already running, you just reattach.

---

## 4. A Second Profile for SSH (No Local tmux)

1. **Create another iTerm2 profile** called “SSH-no-tmux.”  
2. In **General** → **Command**, put:

   ``` bash
   /bin/zsh --login
   ```

   (Or `/bin/bash --login`, `/usr/local/bin/fish`, etc.)  
3. If you have an auto-start line in `~/.zshrc` or `~/.bashrc` like:

   ```bash
   [ -z "$TMUX" ] && exec tmux
   ```

   …wrap it in a condition to skip tmux if `SKIP_LOCAL_TMUX=1`:

   ```bash
   if [ -z "$TMUX" ] && [ -z "$SKIP_LOCAL_TMUX" ]; then
     exec tmux
   fi
   ```

4. Then, in the **SSH-no-tmux** profile’s Command, do:

   ```bash
   env SKIP_LOCAL_TMUX=1 /bin/zsh --login
   ```

   That prevents **any** local tmux from auto-starting, so you get a raw shell—perfect for starting a **remote** tmux session without nesting.

---

## 5. Quickly Open SSH in a New iTerm2 Tab

### 5.1 Use AppleScript and zsh function

add this `ssh` function to your `~/.zshrc`, it will override the original ssh command and avoid breaking any other applications which rely on ssh like scp, rsync, ansible and some zsh plugins.

```bash
# 1) Path to the real ssh
REAL_SSH="$(command -v ssh)"

function ssh() {
  # 2) Non-interactive check: don’t break scripts/tools calling ssh
  if [[ $- != *i* ]]; then
    "$REAL_SSH" "$@"
    return
  fi
  # Check if both stdin and stdout are TTYs.
  # This ensures overriding only in a fully interactive context.
  if [[ ! -t 0 || ! -t 1 ]]; then
    "$REAL_SSH" "$@"
    return
  fi

  # 3) Detect if parent is scp/rsync/sftp via the full command line
  local parent_cmd
  parent_cmd="$(ps -p "$PPID" -o command= 2>/dev/null)"

  case "$parent_cmd" in
    scp*|rsync*|sftp*)
      # If parent is scp/rsync/sftp, just run the real ssh
      "$REAL_SSH" "$@"
      return
      ;;
  esac

  # 4) (Optional) If you only want the override inside local tmux:
  if [[ -n "$TMUX" && -z "$SSH_CONNECTION" ]]; then
    # AppleScript block to open a new iTerm2 tab with a special profile
    osascript <<EOF
tell application "iTerm2"
  if windows is {} then
    set newWindow to create window with profile "SSH-no-tmux"
    tell current session of newWindow
      write text "ssh $*"
    end tell
  else
    tell current window
      create tab with profile "SSH-no-tmux"
      tell current session of current tab
        write text "ssh $*"
      end tell
    end tell
  end if
end tell
EOF

  else
    # Otherwise, run the real ssh
    "$REAL_SSH" "$@"
  fi
}
```
 
- Now you can run: `ssh myserver` to open a new tab in **SSH-no-tmux** profile and jump right into `ssh myserver`.  

---

## 6. Auto-Close the Tab on Logout

When you `exit` a remote SSH session, you may want iTerm2 to close that tab automatically. Older iTerm2 versions had a direct “Close Tab” trigger, but newer versions require using a coprocess script:

1. **Create a small script** in `~/.local/bin/close_iterm_tab.sh`:

     ```bash
    #!/usr/bin/env bash
    osascript <<EOF
    tell application "iTerm2"
    tell current window
        close current tab
    end tell
    end tell
    EOF
    ```

2. Make it executable: `chmod +x ~/.local/bin/close_iterm_tab.sh`
3. In **iTerm2 → Preferences → Profiles → SSH-no-tmux → Triggers**, create a new trigger:
   - **Regular Expression**: `^Connection to .* closed\.`  
   - **Action**: “Run Coprocess…”  
   - **Parameters**: `/Users/<your-username>/.local/bin/close_iterm_tab.sh`

Now, when you log out from an SSH session, iTerm2 sees `Connection to <host> closed.` and runs the script, which in turn closes that tab.

---

## 7. Remote tmux for Persistent Server Sessions

On your local `~/.ssh/config`, you might do:

``` text
Host foo
    HostName foo.b1uepi.xyz
    User ubuntu
    RemoteCommand tmux new-session -A -s username
    RequestTTY yes
    IdentityFile /Users/username/foo/ppk
```

That ensures once you SSH in, you’re automatically in **remote tmux**. If your connection drops, your processes keep running. When you reconnect to remote it will attach to the session automatically

*(If you want a plain shell sometimes, either comment it out or add a condition.)*

---

## 8. Conclusion: No More Nested Nightmares

By having:

- **Default Profile** (auto local tmux)  
- **SSH-no-tmux Profile** (plain shell → remote tmux)  
- A zsh function in zshrc automation to open new tabs quickly  
   Triggers to close tabs when SSH sessions end  

…you **avoid** nested tmux confusion. You get local persistence for local tasks, remote persistence for server tasks, and enjoy a clean, intuitive terminal experience in iTerm2—free from keybinding collisions or mouse-forwarding issues.

Give it a try and say goodbye to the chaos of nesting tmux!
