using System;
using System.ComponentModel;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace CodexTrayManager {
    public sealed class ProcessLease : IDisposable {
        private readonly SafeProcessHandle handle;
        internal ProcessLease(IntPtr handle) { this.handle = new SafeProcessHandle(handle, true); }
        public void Dispose() { handle.Dispose(); }
    }
    public sealed class ProcessRecord {
        public int ProcessId { get; set; }
        public int ParentProcessId { get; set; }
        public string Name { get; set; }
        public DateTime? CreationDate { get; set; }
        public string ExecutablePath { get; set; }
        public string CommandLine { get; set; }
    }
    // Identity is checked on the SAME handle used to terminate. No PID-only kill or /T.
    public static class ProcessControl {
        [DllImport("shell32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern IntPtr CommandLineToArgvW(string commandLine, out int count);
        [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr pointer);
        public static string ProfilePath(string commandLine) {
            if (String.IsNullOrWhiteSpace(commandLine)) return null;
            int count;
            IntPtr argv = CommandLineToArgvW(commandLine, out count);
            if (argv == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            string profile = null;
            try {
                for (int i = 1; i < count; i++) {
                    string argument = Marshal.PtrToStringUni(Marshal.ReadIntPtr(argv, i * IntPtr.Size));
                    string value = null;
                    const string direct = "--user-data-dir=";
                    const string monitor = "--monitor-self-argument=--user-data-dir=";
                    if (argument.StartsWith(direct, StringComparison.OrdinalIgnoreCase)) value = argument.Substring(direct.Length);
                    else if (argument.StartsWith(monitor, StringComparison.OrdinalIgnoreCase)) value = argument.Substring(monitor.Length);
                    else if (argument.Equals("--user-data-dir", StringComparison.OrdinalIgnoreCase) && i + 1 < count)
                        value = Marshal.PtrToStringUni(Marshal.ReadIntPtr(argv, ++i * IntPtr.Size));
                    if (String.IsNullOrWhiteSpace(value)) continue;
                    value = value.Replace('/', '\\').TrimEnd('\\');
                    if (profile != null && !profile.Equals(value, StringComparison.OrdinalIgnoreCase)) return null;
                    profile = value;
                }
                return profile;
            } finally { LocalFree(argv); }
        }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        struct ProcessEntry {
            public uint Size, Usage, ProcessId;
            public UIntPtr DefaultHeap;
            public uint ModuleId, Threads, ParentProcessId;
            public int Priority;
            public uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string ExeFile;
        }
        [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool Process32FirstW(IntPtr snapshot, ref ProcessEntry entry);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool Process32NextW(IntPtr snapshot, ref ProcessEntry entry);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool QueryFullProcessImageNameW(IntPtr process, uint flags, StringBuilder path, ref int size);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool GetProcessTimes(IntPtr h, out long created, out long exit, out long kernel, out long user);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool TerminateProcess(IntPtr h, uint code);
        [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint milliseconds);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll")] static extern void GetSystemTimePreciseAsFileTime(out long fileTime);
        public static ProcessLease AcquireLease(int pid, long expectedFileTime) {
            if (expectedFileTime <= 0) throw new InvalidOperationException("Process creation time is unknown.");
            IntPtr handle = OpenProcess(0x1000u | 0x100000u, false, pid);
            if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                long created, exit, kernel, user;
                if (!GetProcessTimes(handle, out created, out exit, out kernel, out user))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                if (created / 10 != expectedFileTime / 10)
                    throw new InvalidOperationException("Process identity changed while preparing close; retry after refreshing.");
                var lease = new ProcessLease(handle);
                handle = IntPtr.Zero;
                return lease;
            } finally { if (handle != IntPtr.Zero) CloseHandle(handle); }
        }
        public static ProcessRecord[] Snapshot() {
            var records = new List<ProcessRecord>();
            long snapshotStarted;
            GetSystemTimePreciseAsFileTime(out snapshotStarted);
            IntPtr snapshot = CreateToolhelp32Snapshot(2, 0);
            if (snapshot == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                var entry = new ProcessEntry { Size = (uint)Marshal.SizeOf<ProcessEntry>() };
                if (!Process32FirstW(snapshot, ref entry)) throw new Win32Exception(Marshal.GetLastWin32Error());
                do {
                    var record = new ProcessRecord { ProcessId=(int)entry.ProcessId, ParentProcessId=(int)entry.ParentProcessId, Name=entry.ExeFile };
                    IntPtr handle = OpenProcess(0x1000, false, record.ProcessId);
                    if (handle != IntPtr.Zero) {
                        try {
                            long created, exit, kernel, user;
                            // A PID reused after enumeration began must not inherit the old entry's parent.
                            if (GetProcessTimes(handle, out created, out exit, out kernel, out user) && created <= snapshotStarted)
                                record.CreationDate = DateTime.FromFileTimeUtc(created);
                            var path = new StringBuilder(1024);
                            int length = path.Capacity;
                            if (QueryFullProcessImageNameW(handle, 0, path, ref length)) record.ExecutablePath = path.ToString();
                        } finally { CloseHandle(handle); }
                    }
                    records.Add(record);
                } while (Process32NextW(snapshot, ref entry));
                int error = Marshal.GetLastWin32Error();
                if (error != 18) throw new Win32Exception(error);
            } finally { CloseHandle(snapshot); }
            return records.ToArray();
        }
        public static string Inspect(int pid, long expectedFileTime, bool terminate) {
            if (expectedFileTime <= 0) return "UnknownIdentity";
            IntPtr handle = OpenProcess(0x1000u | 0x100000u | (terminate ? 1u : 0u), false, pid);
            if (handle == IntPtr.Zero) {
                int error = Marshal.GetLastWin32Error();
                if (error == 87) return "Gone";
                throw new Win32Exception(error);
            }
            try {
                if (WaitForSingleObject(handle, 0) == 0) return "Gone";
                long created, exit, kernel, user;
                if (!GetProcessTimes(handle, out created, out exit, out kernel, out user))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                // WMI CreationDate has microsecond precision; FILETIME has 100ns precision.
                if (created / 10 != expectedFileTime / 10) return "IdentityChanged";
                if (!terminate) return "Alive";
                if (!TerminateProcess(handle, 1)) {
                    int error = Marshal.GetLastWin32Error();
                    if (WaitForSingleObject(handle, 0) == 0) return "Gone";
                    throw new Win32Exception(error);
                }
                return "TerminationRequested";
            } finally { CloseHandle(handle); }
        }
    }
}
