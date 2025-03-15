import SwiftUI
import Combine
import FamilyControls
import ManagedSettings
import BackgroundTasks

class HomeViewModel: ObservableObject {
    @Published var settings = AppSettings()
    @Published var progress: CGFloat = 0.0
    @Published var isBreak: Bool = false
    @Published var currentCycle: Int = 1
    @Published var isPickerPresented: Bool = false
    @Published var selectedApps = FamilyActivitySelection()
    @Published var timerRunning: Bool = false

    private var timer: AnyCancellable?
    private var store = ManagedSettingsStore()
    private var lastPressTime: Date = Date()
    
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    var timerString: String {
        let time = isBreak ? settings.breakValue : settings.timerValue
        return String(format: "%02d:%02d", time / 60, time % 60)
    }

    init() {
        print("App restarted: Resetting timer and unlocking apps.")

        // Reset timer values to defaults
        settings.timerValue = settings.initialTimerValue
        settings.breakValue = settings.initialBreakValue
        isBreak = false
        currentCycle = 1
        timerRunning = false

        // Ensure apps are unlocked on restart
        unlockApps()
        
        // Remove stored timer states to prevent unwanted resume
        UserDefaults.standard.set(false, forKey: "timerRunning")
        UserDefaults.standard.removeObject(forKey: "savedTimerValue")
        UserDefaults.standard.removeObject(forKey: "savedBreakValue")
        UserDefaults.standard.removeObject(forKey: "isBreak")

        NotificationCenter.default.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appMovedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }



    func handleButtonPress() {
        let currentTime = Date()
        let timeInterval = currentTime.timeIntervalSince(lastPressTime)
        lastPressTime = currentTime

        if timeInterval < 0.5 {
            if isBreak {
                stopTimer()
                isBreak = false
                resetTimerValues()
                unlockApps()
            }
        } else {
            if !timerRunning {
                startTimer()
            } else if isBreak {
                stopTimer()
            }
        }
    }

    func requestScreenTimeAuthorization() {
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                print("Screen Time authorization granted.")
            } catch {
                print("Screen Time authorization failed: \(error.localizedDescription)")
            }
        }
    }


    func startTimer() {
        timerRunning = true
        UserDefaults.standard.set(true, forKey: "timerRunning")
        
        startBackgroundTask() // Keep app alive in background
        
        if isBreak {
            unlockApps()
        } else {
            lockApps()
        }

        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            self.updateTimer()
        }
    }
    
    @objc func appMovedToBackground() {
        print("App moved to background. Keeping timer active if running.")
        
        UserDefaults.standard.set(true, forKey: "appWasBackgrounded") // Mark as backgrounded
        
        if timerRunning {
            UserDefaults.standard.set(settings.timerValue, forKey: "savedTimerValue")
            UserDefaults.standard.set(settings.breakValue, forKey: "savedBreakValue")
            UserDefaults.standard.set(isBreak, forKey: "isBreak")
        }
        
        if backgroundTaskID == .invalid && timerRunning {
            startBackgroundTask()
        }
    }


    @objc func appMovedToForeground() {
        print("App moved to foreground. Resuming tasks.")
        endBackgroundTask() // End any lingering background tasks
        if timerRunning {
            resumeTimer() // Ensure the timer continues running in the foreground
        }
    }

    func updateTimer() {
        if isBreak {
            if settings.breakValue > 0 {
                settings.breakValue -= 1
                progress = CGFloat(settings.initialBreakValue - settings.breakValue) / CGFloat(settings.initialBreakValue)
            } else {
                endBreak()
            }
        } else {
            if settings.timerValue > 0 {
                settings.timerValue -= 1
                progress = CGFloat(settings.initialTimerValue - settings.timerValue) / CGFloat(settings.initialTimerValue)
            } else {
                endWork()
            }
        }
    }

    func endWork() {
        stopTimer()
        unlockApps()
        if currentCycle < settings.totalCycles {
            isBreak = true
            settings.breakValue = settings.initialBreakValue
            startTimer()
        } else {
            resetTimerValues()
        }
    }

    func endBreak() {
        stopTimer()
        lockApps()
        currentCycle += 1
        if currentCycle <= settings.totalCycles {
            isBreak = false
            settings.timerValue = settings.initialTimerValue
            startTimer()
        } else {
            resetTimerValues()
        }
    }

    func stopTimer() {
        timerRunning = false
        UserDefaults.standard.set(false, forKey: "timerRunning")
        timer?.cancel()
        timer = nil
        endBackgroundTask()
    }

    func resetTimerValues() {
        settings.timerValue = settings.initialTimerValue
        settings.breakValue = settings.initialBreakValue
        progress = 0.0
        currentCycle = 1
        stopTimer()
    }

    func applySettings() {
        settings.timerValue = settings.initialTimerValue
        settings.breakValue = settings.initialBreakValue
        resetTimerValues()
    }

    func lockApps() {
        Task {
            guard !selectedApps.applicationTokens.isEmpty else {
                print("No apps selected for locking.")
                return
            }
            store.shield.applications = selectedApps.applicationTokens
            print("Apps locked successfully.")
        }
    }

    func unlockApps() {
        Task {
            store.shield.applications = nil
            print("Apps unlocked successfully.")
        }
    }


    func resumeTimer() {
        guard timerRunning else {
            print("Timer was not running before restart, not resuming.")
            return
        }
        
        let wasRestarted = !UserDefaults.standard.bool(forKey: "appWasBackgrounded")
        
        if wasRestarted {
            print("App was restarted. Timer will not resume automatically.")
            stopTimer()  // Ensure the timer fully stops
            return
        }
        
        print("Resuming existing timer session...")
        startTimer()
    }

    
    // MARK: - Background Task Handling
    private func startBackgroundTask() {
        if backgroundTaskID == .invalid {
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Keep Timer Active") {
                self.endBackgroundTask()
            }
            print("Background task started with ID: \(backgroundTaskID)")
        }
    }

    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            print("Background task ended with ID: \(backgroundTaskID)")
            backgroundTaskID = .invalid
        }
    }
}
