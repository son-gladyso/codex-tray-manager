using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace CodexTrayManager {
    public sealed class WindowRecord {
        public IntPtr Handle { get; set; }
        public int ProcessId { get; set; }
        public bool Visible { get; set; }
        public bool Minimized { get; set; }
        public string Title { get; set; }
        public string ClassName { get; set; }
    }

    public static class NativeMethods {
        [DllImport("user32.dll", SetLastError=true)]
        private static extern bool PostMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);

        public static bool RequestClose(IntPtr handle, int expectedPid) {
            uint pid;
            GetWindowThreadProcessId(handle, out pid);
            return pid == expectedPid && PostMessage(handle, 0x0010, IntPtr.Zero, IntPtr.Zero);
        }
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool BringWindowToTop(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern IntPtr SetActiveWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern IntPtr SetFocus(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr hWnd, StringBuilder text, int maxCount);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern void SwitchToThisWindow(IntPtr hWnd, bool fUnknown);

        public static WindowRecord[] GetTopLevelWindows() {
            var windows = new List<WindowRecord>();
            EnumWindows((hWnd, lParam) => {
                uint processId;
                GetWindowThreadProcessId(hWnd, out processId);
                var title = new StringBuilder(512);
                var className = new StringBuilder(256);
                GetWindowText(hWnd, title, title.Capacity);
                GetClassName(hWnd, className, className.Capacity);
                windows.Add(new WindowRecord {
                    Handle = hWnd,
                    ProcessId = (int)processId,
                    Visible = IsWindowVisible(hWnd),
                    Minimized = IsIconic(hWnd),
                    Title = title.ToString(),
                    ClassName = className.ToString()
                });
                return true;
            }, IntPtr.Zero);
            return windows.ToArray();
        }

        public static bool ActivateWindow(IntPtr hWnd) {
            if (hWnd == IntPtr.Zero) return false;

            // ShowWindowAsync posts to the owner thread; wait for restoration before focus.
            ShowWindowAsync(hWnd, IsIconic(hWnd) ? 9 : 5);
            for (int i = 0; i < 20 && (!IsWindowVisible(hWnd) || IsIconic(hWnd)); i++)
                System.Threading.Thread.Sleep(10);
            if (!IsWindowVisible(hWnd)) return false;

            IntPtr foreground = GetForegroundWindow();
            uint targetProcessId;
            uint foregroundProcessId;
            uint targetThread = GetWindowThreadProcessId(hWnd, out targetProcessId);
            uint foregroundThread = foreground == IntPtr.Zero
                ? 0
                : GetWindowThreadProcessId(foreground, out foregroundProcessId);
            uint currentThread = GetCurrentThreadId();
            bool currentAttached = false;
            bool foregroundAttached = false;

            try {
                if (targetThread != 0 && currentThread != targetThread) {
                    currentAttached = AttachThreadInput(currentThread, targetThread, true);
                }
                if (targetThread != 0 && foregroundThread != 0 &&
                    foregroundThread != targetThread && foregroundThread != currentThread) {
                    foregroundAttached = AttachThreadInput(foregroundThread, targetThread, true);
                }

                ShowWindowAsync(hWnd, 9);
                BringWindowToTop(hWnd);
                SetActiveWindow(hWnd);
                SetFocus(hWnd);
                SetForegroundWindow(hWnd);
                if (GetForegroundWindow() != hWnd) {
                    SwitchToThisWindow(hWnd, true);
                }
                for (int i = 0; i < 10 && GetForegroundWindow() != hWnd; i++)
                    System.Threading.Thread.Sleep(10);
                return IsWindowVisible(hWnd) && GetForegroundWindow() == hWnd;
            }
            finally {
                if (foregroundAttached) {
                    AttachThreadInput(foregroundThread, targetThread, false);
                }
                if (currentAttached) {
                    AttachThreadInput(currentThread, targetThread, false);
                }
            }
        }
    }
}
