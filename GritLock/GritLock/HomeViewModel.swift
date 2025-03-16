import SwiftUI
import Combine
import FamilyControls
import ManagedSettings
import BackgroundTasks

class HomeViewModel: ObservableObject {
    @Published var selectedApps = FamilyActivitySelection() {
            didSet {
                handleSelectionChange()
            }
        }
    @Published var showNoAppsSelectedAlert: Bool = false

    @Published var showGroupSelectionAlert: Bool = false
    @Published var settings = AppSettings()
    @Published var progress: CGFloat = 0.0
    @Published var isBreak: Bool = false
    @Published var currentCycle: Int = 1
    @Published var isPickerPresented: Bool = false
   
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
                // Check if any selections exist - either apps or categories
                if selectedApps.applicationTokens.isEmpty && selectedApps.categoryTokens.isEmpty {
                    showNoAppsSelectedAlert = true
                    return
                }
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
            print("Timer was not running before, not resuming.")
            return
        }
        
        // Only resume if the app was actually backgrounded.
        if UserDefaults.standard.bool(forKey: "appWasBackgrounded") {
            print("Resuming existing timer session...")
            startTimer()
        } else {
            // If the app hasn't been backgrounded (e.g., user navigated to Settings), do nothing.
            print("App was not backgrounded; timer continues running.")
        }
    }


    func applySettings() {
        if !timerRunning {
            settings.timerValue = settings.initialTimerValue
            settings.breakValue = settings.initialBreakValue
            resetTimerValues()
        } else {
            print("Timer is running; not applying new settings.")
        }
    }

   
    func handleSelectionChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { // Delay ensures picker is dismissed
            // Handle category tokens if present
            if !self.selectedApps.categoryTokens.isEmpty {
                // Process the category tokens properly
                self.lockAppsAndCategories()
                return
            }

            // Handle only application tokens
            guard self.store.shield.applications != self.selectedApps.applicationTokens else {
                print("⚠️ Apps are already locked, skipping redundant update.")
                return
            }

            // Lock the selected apps
            self.lockApps()
        }
    }

    func lockAppsAndCategories() {
        Task {
            // Lock individual apps
            DispatchQueue.main.async {
                // Lock apps
                self.store.shield.applications = self.selectedApps.applicationTokens
                
                // Lock categories using the proper policy approach
                let categories = self.selectedApps.categoryTokens
                if !categories.isEmpty {
                    self.store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(categories, except: Set())
                    print("✅ Categories locked: \(categories.count)")
                }
            }
            
            // Save selections for persistence
            do {
                // Save app tokens
                let appData = try PropertyListEncoder().encode(Array(self.selectedApps.applicationTokens))
                UserDefaults.standard.set(appData, forKey: "lockedApps")
                
                // Save category tokens
                if !self.selectedApps.categoryTokens.isEmpty {
                    let categoryData = try PropertyListEncoder().encode(Array(self.selectedApps.categoryTokens))
                    UserDefaults.standard.set(categoryData, forKey: "lockedCategories")
                }
                
                print("✅ Locked apps and categories saved successfully.")
            } catch {
                print("❌ Failed to save locked items: \(error)")
            }
        }
    }
    
    func lockApps() {
        Task {
            // Check if either individual apps or categories are selected
            let hasAppSelection = !selectedApps.applicationTokens.isEmpty
            let hasCategorySelection = !selectedApps.categoryTokens.isEmpty
            
            guard hasAppSelection || hasCategorySelection else {
                print("No apps or categories selected for locking.")
                return
            }

            DispatchQueue.main.async {
                // Lock individual apps if any are selected
                if hasAppSelection {
                    self.store.shield.applications = self.selectedApps.applicationTokens
                    print("✅ Locking \(self.selectedApps.applicationTokens.count) individual apps")
                }
                
                // Lock categories if any are selected
                if hasCategorySelection {
                    let categories = self.selectedApps.categoryTokens
                    self.store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(categories, except: Set())
                    print("✅ Locking \(categories.count) app categories")
                }
            }

            // Save selections to UserDefaults
            do {
                // Save app tokens if any exist
                if hasAppSelection {
                    let appData = try PropertyListEncoder().encode(Array(self.selectedApps.applicationTokens))
                    UserDefaults.standard.set(appData, forKey: "lockedApps")
                }
                
                // Save category tokens if any exist
                if hasCategorySelection {
                    let categoryData = try PropertyListEncoder().encode(Array(self.selectedApps.categoryTokens))
                    UserDefaults.standard.set(categoryData, forKey: "lockedCategories")
                }
                
                print("✅ Locked selections saved successfully.")
            } catch {
                print("❌ Failed to save locked selections: \(error)")
            }

            print("✅ Locking completed successfully.")
        }
    }





    func unlockApps() {
        Task {
            // Unlock apps
            store.shield.applications = nil
            
            // Unlock categories
            store.shield.applicationCategories = nil
            
            print("✅ Apps and categories unlocked successfully.")
        }
    }

    func loadLockedApps() {
        // Initialize a new selection
        selectedApps = FamilyActivitySelection()
        
        // Load individual apps
        if let savedData = UserDefaults.standard.data(forKey: "lockedApps") {
            do {
                let tokens = try PropertyListDecoder().decode([ApplicationToken].self, from: savedData)
                selectedApps.applicationTokens = Set(tokens)
                print("✅ Locked apps restored: \(tokens.count)")
            } catch {
                print("❌ Failed to restore locked apps: \(error)")
            }
        }
        
        // Load categories
        if let savedCategories = UserDefaults.standard.data(forKey: "lockedCategories") {
            do {
                let categoryTokens = try PropertyListDecoder().decode([ActivityCategoryToken].self, from: savedCategories)
                selectedApps.categoryTokens = Set(categoryTokens)
                print("✅ Locked categories restored: \(categoryTokens.count)")
            } catch {
                print("❌ Failed to restore locked categories: \(error)")
            }
        }
        
        // Apply the shield if we have any selections
        if !selectedApps.applicationTokens.isEmpty || !selectedApps.categoryTokens.isEmpty {
            lockAppsAndCategories()
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
