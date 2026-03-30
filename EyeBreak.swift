import Cocoa
import WebKit
import EventKit

// ─────────────────────────────────────────────
// MARK: - Constants
// ─────────────────────────────────────────────

let DEFAULT_INTERVAL: Double = 20 * 60
let BREAK_DURATION:   Double = 20
let INTERVALS: [(label: String, seconds: Double)] = [
    ("10 min", 10 * 60),
    ("15 min", 15 * 60),
    ("20 min", 20 * 60),
    ("30 min", 30 * 60),
    ("45 min", 45 * 60),
]

// ─────────────────────────────────────────────
// MARK: - Calendar Manager
// ─────────────────────────────────────────────

struct CalEvent {
    let time: String
    let name: String
}

class CalendarManager {
    private let store = EKEventStore()
    private var authorized = false

    func requestAccess(completion: @escaping () -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in
                self.authorized = granted
                DispatchQueue.main.async { completion() }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                self.authorized = granted
                DispatchQueue.main.async { completion() }
            }
        }
    }

    func todayEvents() -> [CalEvent] {
        guard authorized else { return [] }
        let cal     = Calendar.current
        let start   = cal.startOfDay(for: Date())
        let end     = cal.date(byAdding: .day, value: 1, to: start)!
        let pred    = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let raw     = store.events(matching: pred)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"

        return raw.map { CalEvent(time: fmt.string(from: $0.startDate), name: $0.title ?? "Untitled") }
    }

    func toJSON(_ events: [CalEvent]) -> String {
        let items = events.map { e -> String in
            let safeName = e.name
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "{\"time\":\"\(e.time)\",\"name\":\"\(safeName)\"}"
        }
        return "[\(items.joined(separator: ","))]"
    }
}

// ─────────────────────────────────────────────
// MARK: - Overlay Window
// ─────────────────────────────────────────────

class CloseHandler: NSObject, WKScriptMessageHandler {
    var onClose: (() -> Void)?
    func userContentController(_ ucc: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        onClose?()
    }
}

class OverlayWindow: NSWindow {
    private var webView: WKWebView!
    private let closeHandler = CloseHandler()
    private var closeTimer: Timer?

    // init(htmlString: String, baseURL: URL) {
    //     let screen = NSScreen.main ?? NSScreen.screens[0]
    //     super.init(
    //         contentRect: screen.frame,
    //         styleMask:   [.borderless],
    //         backing:     .buffered,
    //         defer:       false,
    //         screen:      screen
    //     )
    init(htmlString: String, baseURL: URL) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        super.init(
            contentRect: screen.frame,
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
            // 'screen' parameter removed to call the designated initializer
        )
        self.level
        self.level              = .screenSaver
        self.backgroundColor    = .black
        self.isOpaque           = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let config = WKWebViewConfiguration()
        config.userContentController.add(closeHandler, name: "close")

        let shim = WKUserScript(
            source: "window.close=function(){window.webkit.messageHandlers.close.postMessage('x')};",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(shim)

        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences  = pagePrefs

        webView = WKWebView(frame: CGRect(origin: .zero, size: screen.frame.size),
                            configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        self.contentView = webView

        closeHandler.onClose = { [weak self] in self?.dismiss() }

        webView.loadHTMLString(htmlString, baseURL: baseURL)
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // hard fallback
        closeTimer = Timer.scheduledTimer(withTimeInterval: BREAK_DURATION + 5,
                                          repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        closeTimer?.invalidate()
        closeTimer = nil
        self.orderOut(nil)
        // return focus to whatever was frontmost
        for app in NSWorkspace.shared.runningApplications
            where app.isActive == false && app.activationPolicy == .regular {
            break
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - HTML Builder
// ─────────────────────────────────────────────

func buildHTML(eventsJSON: String) -> String {
    return """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<style>
/* ============================================================
   COLOUR CONFIG — tweak anything here
   ============================================================ */
:root {
  --c-hour-tens:  #F03A8A;
  --c-hour-units: #C844CC;
  --c-colon:      #8855BB;
  --c-min-tens:   #6655E8;
  --c-min-units:  #4477F5;

  --c-bg:        #000000;
  --c-dim:       rgba(255,255,255,0.32);
  --c-mid:       rgba(255,255,255,0.55);
  --c-hi:        rgba(255,255,255,0.88);
  --c-border:    rgba(255,255,255,0.07);

  --c-ev1: #F03A8A; --c-ev2: #6655E8;
  --c-ev3: #4477F5; --c-ev4: #C844CC; --c-ev5: #22BBAA;
}
/* ============================================================ */

*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html,body{width:100%;height:100%;background:var(--c-bg);overflow:hidden;
  font-family:-apple-system,'Helvetica Neue',sans-serif;-webkit-font-smoothing:antialiased;
  display:flex;align-items:center;justify-content:center}
body::before{content:'';position:fixed;inset:0;pointer-events:none;
  background:radial-gradient(ellipse 55% 40% at 28% 50%,rgba(200,68,204,.07) 0%,transparent 100%),
             radial-gradient(ellipse 55% 40% at 72% 50%,rgba(68,119,245,.06) 0%,transparent 100%)}

.card{width:min(880px,92vw);background:rgba(255,255,255,.03);
  border:0.5px solid var(--c-border);border-radius:28px;
  padding:40px 44px 32px;display:flex;flex-direction:column;gap:28px}

.panels{display:flex;align-items:stretch}
.clock-panel{flex:1.1;display:flex;flex-direction:column;align-items:center;
  justify-content:center;gap:20px;padding-right:36px}
.panel-div{width:0.5px;background:var(--c-border);flex-shrink:0;align-self:stretch;margin:4px 0}
.cal-panel{flex:1;display:flex;flex-direction:column;padding-left:36px;gap:16px;justify-content:center}

/* clock */
.clock-row{display:flex;align-items:center;line-height:1}
.digit{font-size:clamp(80px,10vw,124px);font-weight:800;letter-spacing:-3px;
  font-variant-numeric:tabular-nums;transition:color .4s}
.d-h0{color:var(--c-hour-tens)}  .d-h1{color:var(--c-hour-units)}
.d-m0{color:var(--c-min-tens)}   .d-m1{color:var(--c-min-units)}
.d-sep{color:var(--c-colon);font-size:clamp(60px,7.5vw,93px);font-weight:300;
  margin:0 6px;animation:blink 1s step-end infinite;opacity:.85}
@keyframes blink{0%,49%{opacity:.85}50%,100%{opacity:.18}}
.clock-date{font-size:13px;color:var(--c-dim);letter-spacing:.8px;text-transform:uppercase}

/* ring */
.ring-wrap{display:flex;flex-direction:column;align-items:center;gap:7px}
.ring-outer{position:relative;width:72px;height:72px}
.ring-svg{width:72px;height:72px;transform:rotate(-90deg)}
.ring-track{fill:none;stroke:rgba(255,255,255,.07);stroke-width:4.5}
.ring-arc{fill:none;stroke-width:4.5;stroke-linecap:round;stroke:var(--c-min-tens);
  stroke-dasharray:183.78;stroke-dashoffset:0;transition:stroke-dashoffset 1s linear}
.ring-inner{position:absolute;inset:0;display:flex;flex-direction:column;
  align-items:center;justify-content:center}
.ring-num{font-size:22px;font-weight:700;color:#fff;line-height:1}
.ring-unit{font-size:9px;color:var(--c-dim);letter-spacing:1.5px;text-transform:uppercase}
.ring-cap{font-size:10px;color:var(--c-dim);letter-spacing:1.8px;text-transform:uppercase}

/* calendar */
.cal-month{font-size:10px;font-weight:600;color:var(--c-dim);letter-spacing:2.5px;text-transform:uppercase}
.cal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:1px 0;max-width:224px}
.cal-hdr{font-size:9px;color:rgba(255,255,255,.2);text-align:center;padding-bottom:5px;letter-spacing:.5px}
.cal-day{font-size:11px;color:var(--c-dim);text-align:center;
  width:30px;height:30px;display:flex;align-items:center;justify-content:center;border-radius:50%}
.cal-day.faded{color:rgba(255,255,255,.12)}
.cal-day.today{background:var(--c-hour-units);color:#fff;font-weight:700}

/* events */
.ev-head{font-size:9px;font-weight:600;color:rgba(255,255,255,.22);letter-spacing:2px;text-transform:uppercase}
.ev-list{display:flex;flex-direction:column;gap:9px}
.ev-row{display:flex;align-items:flex-start;gap:9px}
.ev-pip{width:5px;height:5px;border-radius:50%;margin-top:4px;flex-shrink:0}
.ev-info{display:flex;flex-direction:column;gap:1px}
.ev-time{font-size:10px;color:var(--c-dim)}
.ev-name{font-size:13px;color:var(--c-hi);white-space:nowrap;overflow:hidden;
  text-overflow:ellipsis;max-width:190px}

/* bottom */
.bottom{border-top:0.5px solid var(--c-border);padding-top:18px;
  display:flex;align-items:center;justify-content:space-between}
.eye-tip{font-size:13px;color:var(--c-dim)}
.eye-tip strong{color:var(--c-hour-units);font-weight:600}
.next-lbl{font-size:11px;color:rgba(255,255,255,.2)}
</style>
</head>
<body>
<div class="card">
  <div class="panels">
    <div class="clock-panel">
      <div class="clock-row">
        <span class="digit d-h0" id="dH0">0</span>
        <span class="digit d-h1" id="dH1">9</span>
        <span class="d-sep">:</span>
        <span class="digit d-m0" id="dM0">4</span>
        <span class="digit d-m1" id="dM1">1</span>
      </div>
      <div class="clock-date" id="clockDate"></div>
      <div class="ring-wrap">
        <div class="ring-outer">
          <svg class="ring-svg" viewBox="0 0 72 72">
            <circle class="ring-track" cx="36" cy="36" r="29.25"/>
            <circle class="ring-arc" cx="36" cy="36" r="29.25" id="ringArc"/>
          </svg>
          <div class="ring-inner">
            <span class="ring-num" id="ringNum">20</span>
            <span class="ring-unit">sec</span>
          </div>
        </div>
        <span class="ring-cap">look away</span>
      </div>
    </div>
    <div class="panel-div"></div>
    <div class="cal-panel">
      <div class="cal-month" id="calMonth"></div>
      <div class="cal-grid" id="calGrid"></div>
      <div class="ev-head">Today's events</div>
      <div class="ev-list" id="evList"></div>
    </div>
  </div>
  <div class="bottom">
    <div class="eye-tip"><strong>Look 20 feet away</strong> — give your eyes a real rest</div>
    <div class="next-lbl" id="nextLbl"></div>
  </div>
</div>
<script>
const CIRC = 2 * Math.PI * 29.25;
const pad  = n => String(n).padStart(2,'0');
const $    = id => document.getElementById(id);
const DAYS   = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
const MONTHS = ['January','February','March','April','May','June','July',
                'August','September','October','November','December'];
const EV_COLORS = ['var(--c-ev1)','var(--c-ev2)','var(--c-ev3)','var(--c-ev4)','var(--c-ev5)'];

// ── clock ──
function tickClock(){
  const n = new Date();
  const h = pad(n.getHours()), m = pad(n.getMinutes());
  $('dH0').textContent = h[0]; $('dH1').textContent = h[1];
  $('dM0').textContent = m[0]; $('dM1').textContent = m[1];
  $('clockDate').textContent = DAYS[n.getDay()] + ', ' + n.getDate() + ' ' + MONTHS[n.getMonth()];
}

// ── calendar ──
function buildCal(){
  const n=new Date(), y=n.getFullYear(), mo=n.getMonth();
  $('calMonth').textContent = MONTHS[mo] + ' ' + y;
  const g=$('calGrid'); g.innerHTML='';
  ['S','M','T','W','T','F','S'].forEach(d=>{
    const el=document.createElement('div'); el.className='cal-hdr'; el.textContent=d; g.appendChild(el);
  });
  const first=new Date(y,mo,1).getDay(), dim=new Date(y,mo+1,0).getDate(), prev=new Date(y,mo,0).getDate();
  for(let i=0;i<first;i++){const el=document.createElement('div');el.className='cal-day faded';el.textContent=prev-first+i+1;g.appendChild(el);}
  for(let d=1;d<=dim;d++){const el=document.createElement('div');el.className='cal-day'+(d===n.getDate()?' today':'');el.textContent=d;g.appendChild(el);}
}

// ── events ──
function buildEvents(){
  const evs = (typeof window.EVENTS_DATA!=='undefined' && window.EVENTS_DATA.length)
    ? window.EVENTS_DATA : [];
  const list=$('evList'); list.innerHTML='';
  if(!evs.length){
    list.innerHTML='<div style="font-size:12px;color:rgba(255,255,255,0.2)">No events today</div>';
    return;
  }
  evs.slice(0,5).forEach((e,i)=>{
    list.innerHTML+=`<div class="ev-row">
      <div class="ev-pip" style="background:${EV_COLORS[i%EV_COLORS.length]}"></div>
      <div class="ev-info"><span class="ev-time">${e.time}</span><span class="ev-name">${e.name}</span></div>
    </div>`;
  });
}

// ── ring countdown ──
let secs = \(Int(BREAK_DURATION));
function setRing(v){
  const off = CIRC*(1-v/\(Int(BREAK_DURATION)));
  $('ringArc').style.strokeDasharray=CIRC;
  $('ringArc').style.strokeDashoffset=off;
  $('ringNum').textContent=v;
}
setRing(secs);
const ringTimer = setInterval(()=>{
  secs--; setRing(Math.max(0,secs));
  if(secs<=0){ clearInterval(ringTimer); window.close(); }
},1000);

tickClock(); buildCal(); buildEvents();
setInterval(tickClock, 1000);
</script>
</body>
</html>
"""
}

// ─────────────────────────────────────────────
// MARK: - App Controller
// ─────────────────────────────────────────────

class AppController: NSObject, NSApplicationDelegate {

    // menu bar
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var nextBreakItem: NSMenuItem!
    var pauseItem: NSMenuItem!

    // state
    var intervalSeconds: Double = UserDefaults.standard.double(forKey: "interval") == 0
        ? DEFAULT_INTERVAL
        : UserDefaults.standard.double(forKey: "interval")
    var paused    = false
    var countdown: Double = 0
    var tickTimer: Timer?

    // overlay
    var overlayWindow: OverlayWindow?

    // calendar
    let calManager = CalendarManager()
    var cachedEvents: [CalEvent] = []
    var baseURL: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    // ── launch ──
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenuBar()
        countdown = intervalSeconds

        calManager.requestAccess {
            self.cachedEvents = self.calManager.todayEvents()
        }

        startTick()
    }

    // ── menu bar ──
    func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()

        menu = NSMenu()

        // next break countdown (disabled, just display)
        nextBreakItem = NSMenuItem(title: "Next break in --:--", action: nil, keyEquivalent: "")
        nextBreakItem.isEnabled = false
        menu.addItem(nextBreakItem)

        menu.addItem(.separator())

        // pause / resume
        pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.target = self
        menu.addItem(pauseItem)

        // test break
        let test = NSMenuItem(title: "Test break now", action: #selector(showBreakNow), keyEquivalent: "t")
        test.target = self
        menu.addItem(test)

        menu.addItem(.separator())

        // interval submenu
        let intervalMenu = NSMenu()
        for opt in INTERVALS {
            let item = NSMenuItem(title: opt.label, action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = opt.seconds
            if opt.seconds == intervalSeconds { item.state = .on }
            intervalMenu.addItem(item)
        }
        let intervalItem = NSMenuItem(title: "Interval", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Eye Break", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func updateIcon() {
        if let btn = statusItem.button {
            btn.title = paused ? "⏸︎" : "🌱"
        }
    }

    // ── timer ──
    func startTick() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func tick() {
        guard !paused else { return }
        countdown -= 1
        updateCountdownLabel()
        if countdown <= 0 {
            countdown = intervalSeconds
            // refresh calendar once a day is fine; refresh on each break
            cachedEvents = calManager.todayEvents()
            showBreak()
        }
    }

    func updateCountdownLabel() {
        let m = Int(countdown) / 60
        let s = Int(countdown) % 60
        let str = String(format: "%02d:%02d", m, s)
        DispatchQueue.main.async {
            self.nextBreakItem.title = self.paused
                ? "Paused"
                : "Next break in \(str)"
        }
    }

    // ── actions ──
    @objc func togglePause() {
        paused.toggle()
        pauseItem.title = paused ? "Resume" : "Pause"
        updateIcon()
        updateCountdownLabel()
    }

    @objc func showBreakNow() {
        cachedEvents = calManager.todayEvents()
        showBreak()
        countdown = intervalSeconds
    }

    @objc func setInterval(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? Double else { return }
        intervalSeconds = secs
        countdown = secs
        UserDefaults.standard.set(secs, forKey: "interval")
        // update checkmarks
        if let sub = sender.menu {
            for item in sub.items { item.state = .off }
            sender.state = .on
        }
        updateCountdownLabel()
    }

    // ── overlay ──
    func showBreak() {
        guard overlayWindow == nil else { return }
        let eventsJSON = calManager.toJSON(cachedEvents)
        var html = buildHTML(eventsJSON: eventsJSON)
        // inject events data
        html = html.replacingOccurrences(
            of: "typeof window.EVENTS_DATA!=='undefined'",
            with: "true"
        )
        let injected = "<script>window.EVENTS_DATA=\(eventsJSON);</script>"
        html = html.replacingOccurrences(of: "</head>", with: injected + "</head>")

        DispatchQueue.main.async {
            self.overlayWindow = OverlayWindow(htmlString: html, baseURL: self.baseURL)
            // clean up reference when dismissed
            DispatchQueue.main.asyncAfter(deadline: .now() + BREAK_DURATION + 6) {
                self.overlayWindow = nil
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Entry Point
// ─────────────────────────────────────────────

let app        = NSApplication.shared
let controller = AppController()
app.delegate   = controller
app.run()
