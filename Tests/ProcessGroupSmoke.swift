import Foundation
import Darwin

let child = Process()
child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
child.arguments = ["-c", "import subprocess,time; subprocess.Popen(['/bin/sleep','30']); time.sleep(30)"]
try child.run()
let group = child.processIdentifier
Thread.sleep(forTimeInterval: 0.4)
guard Darwin.kill(-group, SIGTERM) == 0 else { fatalError("Could not signal the owned process group") }
child.waitUntilExit()
Thread.sleep(forTimeInterval: 0.4)
guard Darwin.kill(-group, 0) == -1 else { fatalError("A process survived in the owned process group") }
print("PASS: SIGTERM stopped the owned parent and child process group")
