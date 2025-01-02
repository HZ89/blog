+++
title = "Turbocharge Your Terminal: A Fun Trick for a Stress-Free tmux + iTerm2 Setup"
date = "2025-01-02T23:01:52+08:00"
#dateFormat = "2006-01-02" # This value can be configured for per-post date formatting
author = "Harrison Zhu"
authorTwitter = "" #do not include @
cover = ""
tags = ["iterm2", "tmux"]
keywords = ["", ""]
description = ""
showFullContent = false
readingTime = "600s"
hideComments = false
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

## 2. Why We Do This

- **Local tmux**:  
  - Keep your **local** scripts, builds, logs, or Docker containers running—even if you close iTerm2 or unplug from the network.  
  - Seamlessly **detach and reattach** to your local environment on your Mac.

- **Remote tmux**:  
  - Keep **remote** tasks alive if the connection drops or if you need to log out.  
  - Easily handle long-running builds, watchers, or logs on your servers without worrying about your laptop’s uptime.

But if you open a local tmux session and then nest a remote tmux session, it leads to the confusion above. The fix: **iTerm2 profiles** so you can choose whether you want local tmux or not, **and** let the remote server handle its own tmux. This way, you have:

- A local tmux for everything happening on your machine.
- A **plain shell** for quick SSH connections—**no** local tmux—so if the remote server is running tmux, you get just one layer.

---

## 3. Auto-Starting Local tmux in iTerm2

### 3.1 Create a Default Profile

1. In **iTerm2 → Preferences → Profiles**, pick your default profile (or create a new one) and set **Command** to something like:
   ```
   /usr/local/bin/tmux new-session -A -s mylocal
   ```
   Adjust the path as necessary (maybe `/opt/homebrew/bin/tmux`). The `-A -s mylocal` means “attach to session `mylocal` if it exists, otherwise create it.”

2. Now, whenever you open a new iTerm2 tab/window with this **Default** profile, you automatically attach a **local** tmux session. If it’s already running, you just reattach.

---

## 4. A Second Profile for SSH (No Local tmux)

1. **Create another iTerm2 profile** called “SSH-no-tmux.”  
2. In **General** → **Command**, put:
   ```
   /bin/zsh --login
   ```
   (Or `/bin/bash --login`, `/usr/local/bin/fish`, etc.)  
3. If you have an auto-start line in `~/.zshrc` or `~/.bashrc` like:
   ```bash
   [ -z "$TMUX" ] && exec tmux
   ```
   …wrap it in a variable check to skip tmux if `SKIP_LOCAL_TMUX=1`:
   ```bash
   if [ -z "$TMUX" ] && [ -z "$SKIP_LOCAL_TMUX" ]; then
     exec tmux
   fi
   ```
4. Then, in the **SSH-no-tmux** profile’s Command, do:
   ```
   env SKIP_LOCAL_TMUX=1 /bin/zsh --login
   ```
   That prevents **any** local tmux from auto-starting, so you get a raw shell—perfect for starting a **remote** tmux session without nesting.

---

## 5. Quickly Open SSH in a New iTerm2 Tab

### 5.1 Use AppleScript

If you want an easy way to open a new tab with the “SSH-no-tmux” profile and immediately run `ssh user@host`, create a script like `sshnt`:

```bash
#!/usr/bin/env bash
if [ -z "$1" ]; then
  echo "Usage: sshnt <host>"
  exit 1
fi
HOST="$1"
shift

osascript <<EOF
tell application "iTerm2"
  if windows is {} then
    set newWindow to create window with profile "SSH-no-tmux"
    tell current session of newWindow
      write text "ssh $HOST $*"
    end tell
  else
    tell current window
      create tab with profile "SSH-no-tmux"
      tell current session of current tab
        write text "ssh $HOST $*"
      end tell
    end tell
  end if
end tell
EOF
```

- Make it executable: `chmod +x ~/.local/bin/sshnt`.  
- Now you can run: `sshnt myserver` to open a new tab in **SSH-no-tmux** profile and jump right into `ssh myserver`.  

---

## 6. Auto-Close the Tab on Logout

When you `exit` a remote SSH session, you might want iTerm2 to close that tab automatically. Older iTerm2 versions had a direct “Close Tab” trigger, but newer ones require a coprocess script:

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

On your remote server’s `~/.bashrc` or `~/.zshrc`, you might do:
```bash
if [ -z "$TMUX" ]; then
  tmux new-session -A -s remote
fi
```
That ensures once you SSH in, you’re automatically in **remote tmux**. If your connection drops, your processes keep running. Just reattach with `tmux attach -t remote`.

*(If you want a plain shell sometimes, either comment it out or add a condition.)*

---

## 8. Conclusion: No More Nested Nightmares

By having:

- **Default Profile** (auto local tmux)  
- **SSH-no-tmux Profile** (plain shell → remote tmux)  
- A script (`sshnt`) or AppleScript automation to open new tabs quickly  
- (Optional) Triggers to close tabs when SSH sessions end  

…you **avoid** nested tmux confusion. You get local persistence for local tasks, remote persistence for server tasks, and a clean, intuitive terminal experience in iTerm2—without the dreaded keybinding collisions or mouse-forwarding issues.

Give it a try and say goodbye to the chaos of nesting tmux!
