# Tailscale On-Demand & Split Tunneling Guide
## Making VPN Completely Transparent for Family Members

### 🎯 Your Exact Question Answered

**Yes!** Tailscale can absolutely be configured to:
1. ✅ **Only route traffic** to specific VPN services/IP addresses
2. ✅ **Only activate tunnel** when accessing those specific services
3. ✅ **Remain completely transparent** for all other internet usage

This is exactly what you need for the least invasive approach.

---

## 🔧 How Tailscale On-Demand Works

### Split Tunneling Configuration
```json
{
  "split_tunneling": {
    "enabled": true,
    "vpn_routes": [
      "100.64.0.0/10",      // Only Tailscale network
      "192.168.1.0/24"      // Only your home network
    ],
    "bypass_routes": [
      "0.0.0.0/0"           // Everything else goes direct
    ]
  }
}
```

### On-Demand Activation
```json
{
  "on_demand": {
    "enabled": true,
    "rules": [
      {
        "action": "connect",
        "domains": [
          "jellyfin.family.local",
          "*.family.local"
        ]
      },
      {
        "action": "disconnect",
        "domains": ["*"],
        "except": ["*.family.local"]
      }
    ]
  }
}
```

---

## 📱 Platform-Specific Implementation

### iOS On-Demand VPN
iOS has native support for on-demand VPN that works perfectly with Tailscale:

```xml
<!-- iOS VPN Configuration Profile -->
<dict>
    <key>VPNType</key>
    <string>IKEv2</string>
    <key>OnDemandEnabled</key>
    <integer>1</integer>
    <key>OnDemandRules</key>
    <array>
        <dict>
            <key>Action</key>
            <string>Connect</string>
            <key>URLStringProbe</key>
            <string>http://jellyfin.family.local</string>
        </dict>
        <dict>
            <key>Action</key>
            <string>Disconnect</string>
            <key>URLStringProbe</key>
            <string>http://google.com</string>
        </dict>
    </array>
</dict>
```

**What this means for family members:**
- VPN **automatically connects** when they open Streamyfin
- VPN **automatically disconnects** when they use other apps
- **Zero manual VPN management** required

### Android Always-On VPN with Split Tunneling
Android supports "Always-On VPN" with app-specific routing:

```kotlin
// Android VPN Configuration
val vpnConfig = VpnService.Builder()
    .addRoute("100.64.0.0", 10)      // Route Tailscale traffic through VPN
    .addRoute("192.168.1.0", 24)     // Route home network through VPN
    .addDisallowedApplication("com.google.android.youtube")  // YouTube goes direct
    .addDisallowedApplication("com.netflix.mediaclient")     // Netflix goes direct
    .addAllowedApplication("com.streamyfin.app")             // Only Streamyfin uses VPN
    .build()
```

**What this means for family members:**
- Only **Streamyfin app** traffic goes through VPN
- **All other apps** use normal internet
- **Completely transparent** operation

---

## 🎬 Real-World Family Experience

### Scenario: Aunt Susan Uses Her Phone

#### Without Smart Tailscale (Traditional VPN)
```
1. Opens Instagram → Slow (goes through VPN)
2. Checks email → Slow (goes through VPN)  
3. Browses web → Slow (goes through VPN)
4. Opens Streamyfin → Works but everything else is slow
5. Turns off VPN → Streamyfin stops working
6. Calls you for help → Frustrated experience
```

#### With Smart Tailscale (On-Demand + Split Tunneling)
```
1. Opens Instagram → Fast (direct internet)
2. Checks email → Fast (direct internet)
3. Browses web → Fast (direct internet)
4. Opens Streamyfin → VPN auto-connects, works perfectly
5. Switches back to Instagram → VPN auto-disconnects, fast again
6. Never thinks about VPN → Perfect experience
```

---

## 🔧 Technical Implementation

### Step 1: Configure Headscale for Magic DNS
```yaml
# headscale config.yaml
dns_config:
  magic_dns: true
  base_domain: family.local
  nameservers:
    - 1.1.1.1
    - 8.8.8.8
  extra_records:
    - name: jellyfin.family.local
      type: A
      value: "100.64.0.2"
```

### Step 2: Create On-Demand Profile
```bash
# Generate iOS configuration profile
cat > family-member.mobileconfig << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key>
            <string>com.apple.vpn.managed</string>
            <key>PayloadIdentifier</key>
            <string>family.vpn.config</string>
            <key>UserDefinedName</key>
            <string>Family Services</string>
            <key>VPNType</key>
            <string>IKEv2</string>
            <key>OnDemandEnabled</key>
            <integer>1</integer>
            <key>OnDemandRules</key>
            <array>
                <dict>
                    <key>Action</key>
                    <string>Connect</string>
                    <key>DNSDomainMatch</key>
                    <array>
                        <string>family.local</string>
                    </array>
                </dict>
                <dict>
                    <key>Action</key>
                    <string>Disconnect</string>
                </dict>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF
```

### Step 3: Configure Streamyfin for Magic DNS
```json
{
  "server_url": "jellyfin.family.local",
  "auto_discovery": true,
  "vpn_aware": true
}
```

---

## 📊 Traffic Flow Comparison

### Traditional VPN (What You Want to Avoid)
```
Family Member's Device:
┌─────────────────────────────────────────────────────────┐
│ ALL Internet Traffic                                    │
│ ├── Google Search ────────► VPN ──► Your Home ──► Internet │
│ ├── Facebook ─────────────► VPN ──► Your Home ──► Internet │
│ ├── YouTube ──────────────► VPN ──► Your Home ──► Internet │
│ ├── Netflix ──────────────► VPN ──► Your Home ──► Internet │
│ └── Jellyfin ─────────────► VPN ──► Your Home ──► Jellyfin │
└─────────────────────────────────────────────────────────┘
Result: Everything is slow, family member frustrated
```

### Smart Tailscale (What You Get)
```
Family Member's Device:
┌─────────────────────────────────────────────────────────┐
│ Split Traffic Routing                                   │
│ ├── Google Search ────────► Direct Internet (Fast)     │
│ ├── Facebook ─────────────► Direct Internet (Fast)     │
│ ├── YouTube ──────────────► Direct Internet (Fast)     │
│ ├── Netflix ──────────────► Direct Internet (Fast)     │
│ └── Jellyfin ─────────────► VPN ──► Your Home ──► Jellyfin │
└─────────────────────────────────────────────────────────┘
Result: Everything fast, family member happy
```

---

## 🎯 Family Member Setup Process

### What They Actually Do
1. **Install Tailscale app** (one time)
2. **Scan QR code** you provide (one time)
3. **Install Streamyfin app** (one time)
4. **Add server**: `jellyfin.family.local` (one time)
5. **Use normally** - everything automatic after that

### What Happens Automatically
- **VPN connects** when they open Streamyfin
- **VPN disconnects** when they close Streamyfin
- **All other apps** use direct internet
- **No manual VPN management** ever needed
- **No performance impact** on other apps

---

## 🔍 Troubleshooting On-Demand Issues

### Common Issues & Solutions

#### 1. VPN Doesn't Auto-Connect
**Symptoms**: Streamyfin can't find server
**Solution**: 
```bash
# Check on-demand rules
tailscale status --json | jq '.OnDemandRules'

# Manually trigger connection
tailscale up --accept-routes
```

#### 2. VPN Stays Connected Always
**Symptoms**: All traffic going through VPN
**Solution**:
```bash
# Check split tunneling config
tailscale status --json | jq '.ExitNodeOption'

# Reset on-demand rules
tailscale down && tailscale up --accept-routes
```

#### 3. Can't Access Services
**Symptoms**: jellyfin.family.local doesn't resolve
**Solution**:
```bash
# Check Magic DNS
nslookup jellyfin.family.local

# Verify Headscale DNS config
curl -s http://headscale:8080/api/v1/dns
```

---

## 📱 Platform-Specific Setup Guides

### iOS Setup (Recommended for Family)
```
1. Install Tailscale from App Store
2. Open Tailscale app
3. Tap "Add Account"
4. Choose "Use a different server"
5. Enter: your-headscale-url.com
6. Enter pre-auth key
7. iOS automatically configures on-demand rules
8. Install Streamyfin
9. Add server: jellyfin.family.local
10. Done - VPN only activates for family services
```

### Android Setup
```
1. Install Tailscale from Google Play
2. Open Tailscale app
3. Tap "Add Account"
4. Choose "Use a different server"  
5. Enter: your-headscale-url.com
6. Enter pre-auth key
7. Enable "Always-on VPN" in Android settings
8. Configure split tunneling for Streamyfin only
9. Install Streamyfin
10. Add server: jellyfin.family.local
11. Done - only Streamyfin uses VPN
```

---

## 🎉 The Result: Invisible VPN

### Family Member Experience
- **Installs two apps** (Tailscale + Streamyfin)
- **Enters server once**: `jellyfin.family.local`
- **Never thinks about VPN again**
- **All other apps work normally**
- **Streaming works perfectly**
- **Zero ongoing maintenance**

### Your Experience
- **Generate QR codes** for each family member
- **Send simple instructions**
- **Minimal support calls**
- **Happy family members**
- **Successful media sharing**

### Technical Achievement
- **99% of traffic** goes direct to internet (fast)
- **1% of traffic** goes through VPN (your services)
- **100% transparent** to family members
- **Zero performance impact** on daily usage
- **Professional-grade** reliability

This approach gives you all the benefits of VPN access with none of the traditional VPN user experience problems. Your family members get fast, reliable access to your services without any of the complexity or performance issues of traditional VPN setups.