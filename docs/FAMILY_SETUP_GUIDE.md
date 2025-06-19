# Family Member Setup Guide
## How to Access Your Personal Media Server

### 📦 What You'll Receive

You'll get a small device (about the size of a deck of cards) that makes your TV able to access our family media server. This device contains thousands of movies, TV shows, and other content.

**In the Box:**
- 📱 Small computer device (Raspberry Pi or similar)
- 🔌 Power adapter
- 📄 This instruction card
- 🏷️ Sticker with your login information

---

## 🚀 Quick Setup (5 Minutes)

### Step 1: Connect the Device
1. **Plug into power** - Connect the power adapter to the small device
2. **Connect to internet** - Plug ethernet cable from your router to the device
   - *OR if no ethernet: The device will create its own WiFi network*
3. **Wait 3 minutes** - The device needs time to start up and connect

### Step 2: Install the App on Your Phone/Tablet

**Option A: Streamyfin (Recommended - Better Experience)**
- **iPhone/iPad**: Search "Streamyfin" in App Store
- **Android**: Search "Streamyfin" in Google Play Store
- **Cost**: Free

**Option B: Official Jellyfin App (Backup Option)**
- **iPhone/iPad**: Search "Jellyfin Mobile" in App Store  
- **Android**: Search "Jellyfin" in Google Play Store
- **Cost**: Free

### Step 3: Connect to Your Media Server

1. **Open the app** you just installed
2. **Add Server** - Look for "Add Server" or "+" button
3. **Enter server address**: `http://192.168.1.100:8096`
   - *Type this exactly as shown*
4. **Login** with the username/password on your sticker

### Step 4: Start Watching!

1. **Browse content** - Scroll through movies and TV shows
2. **Start playing** - Tap any movie or show
3. **Cast to TV** - Tap the cast button (📺) and select your Chromecast
4. **Enjoy!** - Content will start playing on your TV

---

## 📱 Detailed Phone/Tablet Instructions

### Using Streamyfin (Recommended)

**Why Streamyfin is Better:**
- ✅ Faster and more responsive
- ✅ Better video quality
- ✅ Easier to navigate
- ✅ Works better with Chromecast
- ✅ More reliable

**Setup Steps:**
1. **Download**: Install "Streamyfin" from your app store
2. **Open app**: Tap the Streamyfin icon
3. **Add Server**: 
   - Tap "Add Server" or "+"
   - Server URL: `http://192.168.1.100:8096`
   - Server Name: "Family Media" (or whatever you want)
   - Tap "Connect"
4. **Login**:
   - Username: *(from your sticker)*
   - Password: *(from your sticker)*
   - Tap "Sign In"
5. **You're Ready!** You should see the main screen with movies and shows

### Using Official Jellyfin App (Backup)

**If Streamyfin doesn't work for some reason:**
1. **Download**: Install "Jellyfin Mobile" from your app store
2. **Open app**: Tap the Jellyfin icon
3. **Add Server**:
   - Tap "Add Server"
   - Host: `192.168.1.100`
   - Port: `8096`
   - Tap "Connect"
4. **Login** with your username/password
5. **You're Ready!**

---

## 📺 Watching on Your TV

### Method 1: Cast from Phone/Tablet (Easiest)

1. **Make sure** your phone and Chromecast are on the same WiFi network
2. **Open** Streamyfin or Jellyfin app
3. **Find** a movie or show you want to watch
4. **Tap** the movie/show to start playing
5. **Look for cast button** (📺 icon) - usually in top-right corner
6. **Tap cast button** and select your Chromecast from the list
7. **Content starts playing** on your TV automatically

### Method 2: Use TV Browser Directly

**If you don't have a smartphone:**
1. **Open web browser** on your smart TV
2. **Navigate to**: `http://192.168.1.100:8096`
3. **Login** with your username/password
4. **Browse and watch** directly on TV

---

## 🎬 What Content is Available

Your media server includes:
- **Movies**: Latest releases, classics, family films
- **TV Shows**: Current series, complete seasons, documentaries  
- **Kids Content**: Cartoons, educational shows, family movies
- **Music**: Albums, playlists, audiobooks
- **Personal Content**: Family videos, photos

**Content is organized by:**
- Recently Added
- Genres (Action, Comedy, Drama, etc.)
- Collections (Marvel Movies, Star Wars, etc.)
- Continue Watching
- Recommended for You

---

## 🔧 Troubleshooting

### "Can't Find Server" or "Connection Failed"

**Check These Things:**
1. **Device Power**: Is the small device plugged in and powered on?
2. **Internet**: Is your WiFi/internet working normally?
3. **Wait**: Did you wait 3+ minutes after plugging in the device?
4. **Restart**: Unplug the device for 10 seconds, plug back in, wait 3 minutes

**Try These URLs:**
- First try: `http://192.168.1.100:8096`
- If that fails: `http://192.168.0.100:8096`
- If that fails: `http://10.0.0.100:8096`

### "Login Failed" or "Invalid Credentials"

1. **Double-check** username and password from your sticker
2. **Check capitalization** - usernames are case-sensitive
3. **Try typing slowly** to avoid typos

### "Chromecast Not Found" or Can't Cast

1. **Same Network**: Make sure phone and Chromecast are on same WiFi
2. **Restart Chromecast**: Unplug for 10 seconds, plug back in
3. **Restart App**: Close and reopen Streamyfin/Jellyfin app
4. **Check Cast Button**: Look for 📺 icon in app

### Video Won't Play or Keeps Buffering

1. **Check Internet Speed**: Try other apps (YouTube, Netflix) to test
2. **Lower Quality**: In app settings, choose lower video quality
3. **Restart Everything**: Restart app, restart Chromecast, restart bridge device

### Bridge Device Issues

**Status Lights (if visible):**
- 🔴 Red Light Only: Starting up (wait 3 minutes)
- 🟡 Yellow Light: Connecting to internet
- 🟢 Green Light: Ready to use
- 🔴 Red Blinking: Problem (unplug/replug device)

---

## 📞 Getting Help

### Self-Help Options
1. **Restart Everything**: This fixes 80% of issues
   - Unplug bridge device for 10 seconds
   - Restart your phone/tablet
   - Restart Chromecast
   - Wait 3 minutes, try again

2. **Check Status**: Open web browser, go to `http://192.168.1.100:8080`
   - This shows if the bridge device is working

### Contact Support
**If nothing works, contact me:**
- 📱 Text/Call: *(your phone number)*
- 📧 Email: *(your email)*
- 💬 Message: *(your preferred messaging app)*

**When contacting, please tell me:**
- What step you're stuck on
- What error message you see (take a photo)
- What device you're using (iPhone, Android, etc.)

---

## 🎯 Quick Reference Card

**Cut this out and keep it handy:**

```
┌─────────────────────────────────────┐
│        QUICK REFERENCE              │
├─────────────────────────────────────┤
│ Server Address:                     │
│ http://192.168.1.100:8096          │
│                                     │
│ Username: ________________          │
│ Password: ________________          │
│                                     │
│ App: Streamyfin (recommended)       │
│ Backup App: Jellyfin Mobile         │
│                                     │
│ Support: _(your contact info)_      │
└─────────────────────────────────────┘
```

---

## 🌟 Pro Tips for Best Experience

### For Better Performance
- **Use Streamyfin** instead of official Jellyfin app
- **Connect bridge device via ethernet** instead of WiFi when possible
- **Close other apps** when streaming to reduce buffering

### For Easier Navigation
- **Mark favorites** by tapping the heart icon
- **Use "Continue Watching"** to resume where you left off
- **Check "Recently Added"** for new content

### For Multiple Users
- **Each person can have their own account** with separate watch history
- **Kids accounts** can be restricted to appropriate content
- **Create playlists** for movie nights or binge-watching

### For Best Quality
- **Good internet** = better video quality (automatically adjusts)
- **Wired connection** for bridge device = more reliable streaming
- **Close other streaming apps** to free up bandwidth

---

## ❓ Frequently Asked Questions

**Q: Do I need to pay for this?**
A: No! This is our family media server. No monthly fees.

**Q: Is this legal?**
A: Yes, this is our personal media collection shared within our family.

**Q: Can I download movies to watch offline?**
A: Yes! Both Streamyfin and Jellyfin apps support downloading for offline viewing.

**Q: What if I want to watch on multiple TVs?**
A: You can cast to any Chromecast in your house. Just select the right one when casting.

**Q: Can multiple people watch at the same time?**
A: Yes! Multiple family members can watch different things simultaneously.

**Q: What if the device breaks?**
A: Contact me and I'll send a replacement. These devices are very reliable though.

**Q: Can I request specific movies or shows?**
A: Absolutely! Just let me know what you'd like and I'll add it to the server.

---

*This guide was created to be as simple as possible. If anything is confusing or doesn't work, please don't hesitate to contact me for help!*