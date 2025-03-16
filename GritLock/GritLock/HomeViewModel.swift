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

        // Restore locked apps
        loadLockedApps()  


        // Remove stored timer states to prevent unwanted resume
        UserDefaults.standard.set(false, forKey: "timerRunning")
        UserDefaults.standard.removeObject(forKey: "savedTimerValue")
        UserDefaults.standard.removeObject(forKey: "savedBreakValue")
        UserDefaults.standard.removeObject(forKey: "isBreak")

        NotificationCenter.default.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appMovedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)

        registerBackgroundTask()
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

        scheduleBackgroundTask() // ✅ Schedule long-running background task

        if isBreak {
            unlockApps()
        } else {
            lockApps()
        }

        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.updateTimer()
        }
    }

    @objc func appMovedToBackground() {
        print("App moved to background. Keeping timer active if running.")
        UserDefaults.standard.set(true, forKey: "appWasBackgrounded")

        if timerRunning {
            scheduleBackgroundTask() // ✅ Keep timer running in the background
        }
    }

    @objc func appMovedToForeground() {
        print("App moved to foreground. Resuming tasks.")
        if timerRunning {
            resumeTimer()
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
        cancelBackgroundTask()
    }

    func resetTimerValues() {
        settings.timerValue = settings.initialTimerValue
        settings.breakValue = settings.initialBreakValue
        progress = 0.0
        currentCycle = 1
        stopTimer()
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

            do {
                let encodedData = try PropertyListEncoder().encode(Array(selectedApps.applicationTokens))
                UserDefaults.standard.set(encodedData, forKey: "lockedApps")
                print("✅ Locked apps saved successfully.")
            } catch {
                print("❌ Failed to save locked apps: \(error)")
            }

            store.shield.applications = selectedApps.applicationTokens
            print("✅ Apps locked successfully.")
        }
    }


    
    func unlockApps() {
        Task {
            store.shield.applications = nil
            print("Apps unlocked successfully.")
        }
    }
    func loadLockedApps() {
        guard let savedData = UserDefaults.standard.data(forKey: "lockedApps") else {
            print("🔍 No locked apps found in storage.")
            return
        }

        do {
            let tokens = try PropertyListDecoder().decode([ApplicationToken].self, from: savedData)

            // ✅ Correct way to set selectedApps
            selectedApps = FamilyActivitySelection()
            selectedApps.applicationTokens = Set(tokens) // ✅ Correct property name

            store.shield.applications = selectedApps.applicationTokens
            print("✅ Locked apps restored successfully.")
        } catch {
            print("❌ Failed to restore locked apps: \(error)")
        }
    }




   


    // ✅ Register Background Task
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "GritLock.GritLock.timerTask", using: nil) { task in
            self.handleBackgroundTask(task: task as! BGProcessingTask)
        }
    }

    // ✅ Schedule Background Task
    private func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: "GritLock.GritLock.timerTask")
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // Runs every 5 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background task scheduled successfully")
        } catch {
            print("❌ Failed to schedule background task: \(error)")
        }
    }

    // ✅ Handle Background Task Execution
    private func handleBackgroundTask(task: BGProcessingTask) {
        task.expirationHandler = {
            print("❌ Background task expired")
            self.cancelBackgroundTask()
        }

        startTimer() // Resume timer when background task runs
        task.setTaskCompleted(success: true)
    }

    // ✅ Cancel Background Task
    private func cancelBackgroundTask() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
        print("✅ All background tasks canceled")
    }
}
