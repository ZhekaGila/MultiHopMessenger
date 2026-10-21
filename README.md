# MultiHopMessenger

**Development and Evaluation of a Multi-Hop Messaging System for Android Smartphones under Intermittent Network Connectivity**

**Software Engineering | SE-2421 | First Pre-Defense - 24 October 2026**

MultiHopMessenger is a research-oriented Android messaging prototype exploring communication between nearby smartphones without an Internet connection. The project investigates **opportunistic store-and-forward messaging**: a device may keep a message locally and pass it to another device when a suitable connection becomes available.

The current repository contains an **early Flutter/Android implementation** with Bluetooth Classic communication, local message storage, and preliminary relay-handling logic. A complete multi-hop routing evaluation has **not yet been demonstrated**.

## 1. Problem and motivation

Conventional Internet-based messaging depends on network availability. In locations with weak coverage or during temporary outages, a continuous path between two smartphones may not exist. Opportunistic networking offers a way to investigate delayed delivery using intermittent device-to-device contacts.

Potential users include Android smartphone owners who experience connectivity interruptions, such as students, travelers, and people in areas with limited network coverage. The prototype is intended for **research and controlled testing**, not as a production messenger, emergency communication guarantee, or replacement for SMS.

## 2. Research focus

**Research question:**

- How do forwarding strategy (Epidemic versus Binary Spray-and-Wait) and controlled disconnection duration affect message delivery ratio, creation-to-delivery latency, and forwarding overhead in a small indoor Android smartphone network?

**Aim:** Evaluate the delivery reliability, waiting-inclusive latency, and forwarding cost of Epidemic and Binary Spray-and-Wait under controlled disconnection durations on compatible Android smartphones.

**Objectives:**

1. Define repeatable phone configurations, message workloads, contact schedules, message lifetime rules, and event-log formats.
2. Compare message delivery ratio under both forwarding strategies and planned disconnections.
3. Analyze creation-to-delivery latency and the time required to deliver queued messages after renewed contact.
4. Measure forwarding overhead and interpret the trade-offs between delivery, latency, and transmission cost.

## 3. Team and supervision

| **Team member** | **Responsibility** |
| --- | --- |
| **Zaman Baldauren Abylkanqyzy** | Android application interface, user interactions, and mobile application integration |
| **Gilazhev Zhandos Zhasulanuly** | Device-to-device communication, Bluetooth integration, forwarding and routing logic |
| **Abdraiym Zhaniya Maratkyzy** | Research design, user-needs evidence, testing procedures, data collection, and analysis |

**Supervisor:** Kutpanova Zarina Almabekovna  
**Educational program:** Software Engineering  
**Group:** SE-2421

Each team member is expected to contribute using an individual GitHub account and to link substantial work to the relevant task in YouTrack.

## 4. Technology stack

| **Component** | **Technology** | **Current use** |
| --- | --- | --- |
| Android user interface | **Flutter / Dart** | Screens, chat interactions, device and connection controls |
| Native Android communication | **Kotlin / Android Bluetooth API** | Bluetooth Classic RFCOMM server/client connections |
| Flutter-Android integration | **MethodChannel / EventChannel** | Native commands and asynchronous status/message events |
| Local message persistence | **SQLite (sqflite)** | Message records, status, and hop count |
| Message identity | **UUID (uuid)** | Unique message IDs |
| Device identity | **shared_preferences** | Locally persisted device UUID |
| Source control and work tracking | **GitHub / YouTrack** | Repository history and assigned tasks |

The current Bluetooth interface lists **previously paired devices**; automatic discovery of unpaired nearby phones is not established by this code snapshot.

## 5. Implementation status

The following distinction is important for the first pre-defense: **implemented in source code** does not automatically mean **validated on all target phones**.

| **Feature** | **Status** | **Evidence / limitation** |
| --- | --- | --- |
| Flutter Android interface | **Implemented in code** | lib/main.dart |
| Bluetooth permission requests and connection controls | **Implemented in code** | Native Kotlin activity and Android manifest |
| Bluetooth Classic RFCOMM server/client and text transfer | **Implemented in code** | android/app/src/main/kotlin/com/example/multihop_messenger/MainActivity.kt |
| Display previously paired Bluetooth devices | **Implemented in code** | Paired-device list exposed to Flutter |
| Local device UUID and message UUID | **Implemented in code** | device_identity.dart, message.dart |
| SQLite message records | **Implemented in code** | database_helper.dart |
| Preliminary relay-message storage, duplicate-ID handling, hop-count limit | **Partially implemented** | Message insertion and forwarding handlers in lib/main.dart |
| Reliable offline queueing of newly composed messages before a connection | **Not yet verified / incomplete** | The current send action requires an active Bluetooth connection |
| General multi-hop forwarding through arbitrary available relays | **Not yet verified / incomplete** | Current forwarding is primarily destination-ID driven |
| Epidemic forwarding | **Planned for research comparison** | No complete policy implementation confirmed in this snapshot |
| Binary Spray-and-Wait forwarding | **Planned for research comparison** | No copy-token algorithm confirmed in this snapshot |
| Complete delivery acknowledgments, TTL expiry, automatic retry | **Planned / incomplete** | To be designed and tested |
| Structured experimental event logs and metric export | **Planned** | Needed for reproducible evaluation |
| End-to-end message encryption | **Not implemented / not claimed** | Do not use real private conversations for tests |

The development team has reported preliminary Bluetooth connectivity success. The source-code review alone does **not** establish repeatable end-to-end or multi-hop performance measurements.

## 6. Repository structure

The main project files are organized like this:

```text
MultiHopMessenger/
    android/
        app/
            src/
                main/
                    AndroidManifest.xml
                    kotlin/
                        com/example/multihop_messenger/
                            MainActivity.kt

    lib/
        database/
            database_helper.dart
        models/
            message.dart
        services/
            device_identity.dart
        main.dart

    pubspec.yaml
    pubspec.lock
    analysis_options.yaml
    .gitignore
    README.md
```

Most of the Flutter app is in `lib/`. The Bluetooth connection code is in `MainActivity.kt` under `android/`. We use `pubspec.yaml` for dependencies.

The research documents, diagrams, and prototype screenshots will be added to the repository after they are finalized.

## 7. Setup and run

### Prerequisites

- Flutter SDK supporting the Dart SDK constraint in [`pubspec.yaml`](pubspec.yaml) (^3.13.5).
- Android Studio or another configured Android SDK environment.
- Two **physical Android smartphones** with Bluetooth Classic support.
- Bluetooth enabled and the two phones paired through Android settings before connecting inside the app.
- Permission to use the devices for testing.

This is an **Android-focused prototype**; Bluetooth Classic functionality relies on the native Android implementation. An emulator alone is not an adequate test of device-to-device radio behavior.

### Run the app

Clone the repository:

```bash
git clone https://github.com/ZhekaGila/MultiHopMessenger.git
cd MultiHopMessenger
```

Install dependencies, check connected devices, and launch:

```bash
flutter pub get
flutter devices
flutter run
```

To install on two phones, repeat `flutter run` with the appropriate device ID (obtain IDs using `flutter devices`):

```bash
flutter run -d <android-device-id>
```

If the build environment does not satisfy the Dart SDK constraint, install a compatible Flutter release rather than changing dependency versions without review.

### Basic direct-message walkthrough

1. Install and open MultiHopMessenger on both Android phones, enable Bluetooth, and pair the phones in **Android Settings**.
2. In the app, select **Request Bluetooth Permission** where required and **Check Bluetooth**.
3. On the receiving phone, tap **Start Server**.
4. On the sending phone, tap **Show Paired Devices** and select the receiving phone to establish a connection.
5. Confirm that both apps show a connection status and exchange device UUIDs.
6. For direct delivery, use the peer's UUID as the destination (or leave the destination field empty, where supported by the current UI).
7. Enter a **single-line** synthetic text message and send it. Observe the message display and local storage behavior.
8. Tap **Disconnect** when finished.

**Current constraints:** Only one active RFCOMM connection is managed at a time in the native component; unpaired-device scanning is not implemented through the visible UI. The current send action also requires an active connection. These conditions limit the scenarios that can already be demonstrated.

## 8. Testing and evaluation plan

The intended evaluation uses **three to five compatible Android devices**, a consistent app build, and controlled contact schedules.

| **Scenario** | **Purpose** | **Evidence to collect** |
| --- | --- | --- |
| S0 - Direct connection | Establish a one-hop communication baseline | Send/receive IDs and connection events |
| S1 - Relay / multi-hop | Test delivery through at least one intermediate device | Per-hop message events and final receipt |
| S2 - Short interruption | Test storage and forwarding after a shorter planned outage | Queue events, reconnection, delivery outcome |
| S3 - Longer interruption | Compare delivery behavior under a longer outage | Delivery ratio, waiting-inclusive latency, forwarding cost |

Planned primary measures:

- **Message Delivery Ratio (MDR)** = delivered unique message IDs / generated unique message IDs × 100%.
- **Creation-to-delivery latency** = destination receipt time - source creation time, for delivered messages; device-clock consistency must be checked.
- **Forwarding overhead** = counted device-to-device transmission attempts / successfully delivered messages, with retransmission counting defined in the experiment protocol.
- **Hop count** = number of wireless transfers on the successful delivery path.

**Experimental results are not included in this README.** The final policy comparison requires tested implementations of Epidemic and Binary Spray-and-Wait, repeatable conditions, and anonymized event logs.

### Existing checks

```bash
flutter analyze
```

Unit/integration tests for routing policies, persistence, and measured delivery should be added as the prototype matures. The uploaded source snapshot does not include a verified automated test suite.

## 9. User research and privacy

An initial anonymous Google Forms questionnaire received **seven responses** from students reported to be at Astana IT University. Preliminary findings identified interest in connectivity-independent messaging, fast delivery, visible delivery status, and privacy-aware design. The sample is small and is **not representative** of all students or Android users.

- Use synthetic test text rather than personal conversations.
- Obtain consent from device owners before experiments.
- Avoid collecting contact lists or unnecessary personal identifiers.
- Anonymize device IDs and export files used for research.
- Do not claim end-to-end encryption unless it is implemented and verified.

## 10. Project management and milestones

Project tasks, responsibilities, and acceptance criteria are tracked in YouTrack. One existing task is:

- [MHM-14 - Conduct Real-Device Multi-Hop Routing Experiments](https://zhandos.youtrack.cloud/issue/MHM-14/Conduct-Real-Device-Multi-Hop-Routing-Experiments)

Planned milestones:

1. **Research and design:** proposal, user evidence, scientific literature, comparisons, requirements, and architecture.
2. **Direct communication:** validate Bluetooth connectivity and short-text transfer on physical phones.
3. **Multi-hop implementation:** strengthen persistent store-and-forward behavior and implement both forwarding policies.
4. **Experimental evaluation:** controlled outages, logging, metric calculations, and comparison of policies.
5. **Final documentation and defense:** reproducible results, limitations, conclusions, and presentation.

Individual contributions should be visible through identifiable commits and linked tasks. Supervisor comments and corresponding revisions should be recorded only after actual review.

## 11. Known limitations and next steps

- Confirm the Bluetooth transport on each intended Android model and Android version.
- Test queue survival across interruptions and application restarts.
- Verify relay behavior with at least three real phones and rule out unintended direct connectivity.
- Implement and validate **Epidemic** and **Binary Spray-and-Wait** as distinct routing strategies.
- Define and implement delivery acknowledgments, TTL handling, duplicate suppression, and bounded retries.
- Add exportable event logs and repeatable analysis scripts.
- Add automated tests and complete pre-defense documentation and traceability.

## 12. Project links

- **Repository:** [https://github.com/ZhekaGila/MultiHopMessenger](https://github.com/ZhekaGila/MultiHopMessenger)
- **YouTrack task example:** [https://zhandos.youtrack.cloud/issue/MHM-14/Conduct-Real-Device-Multi-Hop-Routing-Experiments](https://zhandos.youtrack.cloud/issue/MHM-14/Conduct-Real-Device-Multi-Hop-Routing-Experiments)
- **Project report and supporting documentation:** To be linked here after files are added to the repository.
- **Pre-defense submission tag:** To be linked after the team publishes the required checkpoint tag.

---

**Academic research prototype - work in progress.** All feature claims and performance conclusions should be supported by source code, reproducible demonstrations, and experimental evidence.
