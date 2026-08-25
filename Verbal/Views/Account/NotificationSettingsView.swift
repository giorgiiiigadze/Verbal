//
//  NotificationSettingsView.swift
//  Verbal
//
//  Controls for local reminders tied to upcoming quotes.
//

import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @AppStorage(ScheduledVisitNotifications.enabledKey) private var remindersEnabled = true
    @AppStorage(ScheduledVisitNotifications.leadTimeKey) private var leadTimeRaw = ScheduledVisitReminderLeadTime.atTime.rawValue

    @Environment(SessionStore.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var toast: Toast?

    private var leadTime: Binding<ScheduledVisitReminderLeadTime> {
        Binding(
            get: { ScheduledVisitReminderLeadTime(rawValue: leadTimeRaw) ?? .atTime },
            set: { option in
                leadTimeRaw = option.rawValue
                Task { await rescheduleReminders() }
            }
        )
    }

    var body: some View {
        List {
            Section {
                Toggle("Upcoming quote reminders", isOn: $remindersEnabled)
                    .tint(.green)
                    .onChange(of: remindersEnabled) { _, enabled in
                        Task {
                            if enabled {
                                await rescheduleReminders()
                            } else {
                                ScheduledVisitNotifications.cancelAll(visits: session.visitStore.visits)
                            }
                            await refreshAuthorizationStatus()
                        }
                    }

                Picker("Remind me", selection: leadTime) {
                    ForEach(ScheduledVisitReminderLeadTime.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .disabled(!remindersEnabled)
            } header: {
                Text("Upcoming")
            } footer: {
                Text("Verbal can remind you when a booked visit is coming up, so you can record the quote while the job is fresh.")
            }
            .listRowBackground(Color(.cardSurface))

            Section {
                LabeledContent("Permission", value: permissionLabel)
                if authorizationStatus == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Open iOS Settings", systemImage: "gear")
                    }
                }
            } footer: {
                Text(permissionFooter)
            }
            .listRowBackground(Color(.cardSurface))
        }
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAuthorizationStatus() }
        .toast($toast)
    }

    private var permissionLabel: String {
        switch authorizationStatus {
        case .notDetermined: return "Not asked"
        case .denied: return "Off"
        case .authorized, .provisional, .ephemeral: return "On"
        @unknown default: return "Unknown"
        }
    }

    private var permissionFooter: String {
        switch authorizationStatus {
        case .denied:
            return "Notifications are blocked in iOS Settings. Turn them on there to receive upcoming quote reminders."
        case .notDetermined:
            return "iOS will ask for permission the next time reminders are enabled or a visit is saved."
        default:
            return "Permission is active for local reminders on this device."
        }
    }

    private func refreshAuthorizationStatus() async {
        authorizationStatus = await ScheduledVisitNotifications.authorizationStatus()
    }

    private func rescheduleReminders() async {
        await ScheduledVisitNotifications.rescheduleAll(visits: session.visitStore.visits)
        await refreshAuthorizationStatus()
        if authorizationStatus == .denied {
            toast = Toast(style: .error, message: "Notifications are off in iOS Settings")
        }
    }
}
