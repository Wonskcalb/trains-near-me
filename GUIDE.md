# Install and user guide

This guide is for everyone, including people who have never written code. Plan about 30 minutes, most of it spent downloading Xcode.

**Trains near me** is a macOS widget showing the next direct trains for one journey, such as Grenoble → Voiron, with real-time delays and cancellations.

![Small and medium widgets](Design/widget-light.png)

![Large widget, NO SERVICE and end of service](Design/widget-states.png)

## Why do I have to build it myself?

The app is not on the Mac App Store, because publishing there costs $99/year. Instead, you build it on your own Mac with Xcode and your Apple account. It's **free**, and a script does almost everything.

Unlike on iPhone, the result does not expire after 7 days. Only your account's certificate expires, after a year, and renewing it takes a minute (see [Troubleshooting](#troubleshooting)).

## What you need

- A Mac running **macOS 15 (Sequoia) or later**.
- About **15 GB of free space**, for Xcode.
- An **Apple Account**. Your App Store or iCloud one works.
- An email address for the free SNCF API token.

---

## 1. Install Xcode

1. Open the **App Store**, search for **Xcode** and install it. Xcode is Apple's free app-building tool, and the download is large.
2. Open Xcode once. Accept the license and let it install its components. If it offers extra platforms (iOS, etc.), you don't need them.

## 2. Connect your Apple Account to Xcode

1. In Xcode, open the **Xcode › Settings…** menu, then the **Accounts** tab.
2. Click **+** at the bottom left, choose **Apple ID**, and sign in. A team named "*Your Name (Personal Team)*" appears.
3. Select that team, click **Manage Certificates…**, then **+** › **Apple Development**. Close the window.

This certificate lets your Mac sign the app. It stays on your Mac and is never shared.

## 3. Get your SNCF API token

1. Go to <https://numerique.sncf.com/startup/api/token-developpeur/> and fill in the form. The page is in French; it asks for your name and email.
2. The token arrives by email. It looks like `3b036afe-0110-4202-b9ed-99718476c2e0`.
3. It can take a few minutes to start working.

The token is free and limited to 5,000 requests per day, far more than you need: the widget makes about one request every 15 minutes.

## 4. Download and install the app

1. Get the code. On <https://github.com/Wonskcalb/trains-near-me>, click the green **Code** button › **Download ZIP**, then double-click the ZIP to unzip it. If you know git, use `git clone` instead.
2. Open the **Terminal** app with Spotlight: press ⌘ + Space and type "Terminal".
3. Type `cd ` (with a trailing space), drag the unzipped folder into the Terminal window, then press Return.
4. Run the installer:

   ```bash
   sh scripts/install.sh
   ```

The script:
- detects your account;
- builds the app, which takes a minute or two the first time;
- installs it in **Applications**;
- opens it.

If a dialog says **codesign** wants to access a keychain key, enter your Mac login password and choose **Always Allow**.

## 5. Set up the app

The **Trains near me** window opens.

1. **SNCF API token**: paste your token, then click **Save and test**. The message "Token works." confirms it's working.
2. **Location**: accept the location prompt if you want "nearest station" mode (see step 7). Otherwise decline it; everything else still works.

You can then close the window. The widget works without the app running.

## 6. Add the widget

1. Right-click the desktop › **Edit Widgets…**
2. Search for **Trains near me**.
3. Pick a size:

   | Size | Content |
   |---|---|
   | Small | 3 trains |
   | **Medium** (recommended) | 3 trains and the last-update time |
   | Large | 8 trains |

4. Drag it onto the desktop or into Notification Center.

The widget first shows "Choose stations". That's expected.

## 7. Choose your journey

Right-click the widget › **Edit "Trains near me"**.

| Setting | What it does |
|---|---|
| **Departure** | Departure station. Type a few letters ("greno") and pick from the list. |
| **Arrival** | Arrival station. |
| **Direction** | **Departure → Arrival**: always this way. **Arrival → Departure**: always the other way. **Automatic**: outbound in the morning, return in the afternoon. |
| **Switch time** | Shown in Automatic mode. When the direction flips; 13:00 by default. |
| **Depart from nearest station** | Whichever of the two stations is closer to you becomes the departure. This overrides **Direction**. |

Only **direct trains** between the two stations are shown, never connections.

Your location is only used on your Mac to compare the distance to the two stations. It never leaves your Mac.

## Reading the widget

```
○ Grenoble                  17:40   ← departure station, last update
● Voiron                            ← arrival station
17:42  25 min                       ← scheduled time, journey duration
18:12  24 min              +12      ← 12 minutes late
```

### Train states

| What you see | Meaning |
|---|---|
| Plain row | On time, or up to 10 min late |
| Orange row, `+12` | 11 to 19 min late |
| Red row, `+23` | 20 min late or more |
| Struck-through time, `CANCELLED` | Train cancelled |
| Orange row, `delay ?` | SNCF reports a disruption but no delay figure |

### Whole-widget states

| What you see | Meaning |
|---|---|
| **NO SERVICE** on orange-and-black stripes | Something is wrong: every remaining train of the day is cancelled |
| **End of service** on a night-blue background | Nothing is wrong, the last train of the day has left. Shows when the first train runs, usually tomorrow morning. |
| **No trains** | SNCF found no direct train at all between the two stations |
| **SNCF data unavailable** | No internet, invalid token, quota reached, or the SNCF API is down. The reason is shown below the title. |
| **Data out of date** | The data is more than 30 min old. The widget never shows old times as if they were current. |
| Orange **Location…** / **No location…** line | Nearest-station mode is on but your location is unavailable. The configured direction is used; click the widget to refresh. |

### How fresh is the data?

macOS, not the app, decides when the widget refreshes: roughly every 15–30 minutes, and less often while the Mac sleeps. The time at the top right shows the last update. For minute-by-minute information, use the SNCF Connect app.

---

## Updating

1. Download the new version, as a ZIP or with `git pull`.
2. Run `sh scripts/install.sh` again from its folder.
3. If the widget's name or look changed, remove the widget and add it again.

If you start from a fresh ZIP, first copy `Config/Local.xcconfig` over from the old folder. It holds your identifiers, which keeps your token and location permission.

## Uninstalling

1. Remove the widget: right-click it › **Remove Widget**.
2. Move **Applications › Trains near me** to the Trash.
3. Optional, to also erase the token: delete the folder `~/Library/Group Containers/<team>.io.github.<you>.trainsnearme`. In the Finder, use **Go › Go to Folder…**, type `~/Library/Group Containers`, and look for the name containing `trainsnearme`.

## Troubleshooting

**"Xcode is required"**
Xcode isn't installed or has never been opened. Do step 1.

**"No Apple Development certificate found"**
The certificate wasn't created. Do step 2, item 3.

**Signing error during the build ("No signing certificate", "requires a development team")**
Open Xcode › Settings › Accounts and check that you're signed in. If you belong to several teams, open `Config/Local.xcconfig` in TextEdit, put the right team id on the `DEVELOPMENT_TEAM` line, then run the script again.

**"Token rejected" in the app, or "The SNCF API token was rejected" in the widget**
Check that the whole token was pasted, without spaces. A brand-new token can take a few minutes to activate.

**Station search returns nothing, or shows "Add your SNCF API token…"**
The token isn't saved. Open the app again, paste it and click **Save and test**.

**"SNCF API daily quota reached"**
The 5,000 requests for the day are used up. This happens when the same token is used on several Macs or in other tools. The quota resets the next day.

**The widget doesn't appear in the gallery, or keeps an old name**
Open the app once. If that's not enough, log out of macOS and back in.

**Orange "Location not allowed" line**
Open **System Settings › Privacy & Security › Location Services** and turn on **Trains near me**. If the app isn't listed, open it once: it asks for permission at launch.

**Orange "No location: click to refresh" line**
macOS gives widgets a location fix reliably only while the app is active. Click the widget: it opens the app, which refreshes the widget with your position. The configured direction is used until then.

**The journey runs the wrong way**
Check **Direction** and **Switch time** in the widget settings. With **Depart from nearest station** on, your location decides.

**The widget stops updating, or the app won't open, after a year**
The certificate expired. Repeat step 2, item 3, to create a new one, then run `sh scripts/install.sh` again.

**Still stuck?**
Open an issue at <https://github.com/Wonskcalb/trains-near-me/issues> describing what you see. Never paste your token there.

## Privacy

- No intermediate server: your Mac talks directly to `api.sncf.com`.
- Your location, if you allow it, is only used on your Mac.
- No analytics and no tracking.
- Your token is stored only on your Mac.

*Independent project, not affiliated with SNCF. Data © SNCF.*
