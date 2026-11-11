// Starts a program on a new, hidden Windows desktop and waits for it
// (tools/render_run.ps1). Its windows exist only on that desktop, which is
// never switched to: nothing shows on the user's screen or taskbar, and it
// can't take focus. The desktop is closed once the program has exited.
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class FlapjawHiddenDesktop
{
    const uint GENERIC_ALL = 0x10000000;
    const uint CREATE_NO_WINDOW = 0x08000000;
    const uint BELOW_NORMAL_PRIORITY_CLASS = 0x00004000;
    const uint WAIT_TIMEOUT = 0x00000102;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION
    {
        public IntPtr hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateDesktop(string name, IntPtr device, IntPtr devmode, int flags, uint access, IntPtr attributes);

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool CloseDesktop(IntPtr desktop);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcess(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit,
        uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint WaitForSingleObject(IntPtr handle, uint ms);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetExitCodeProcess(IntPtr process, out uint code);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool TerminateProcess(IntPtr process, uint code);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);

    /// Runs `exe args` on a fresh hidden desktop; returns its exit code, or -1
    /// when it was stopped after `timeoutMs`. Throws if it can't start.
    public static int Run(string exe, string args, string cwd, int timeoutMs)
    {
        string name = "FlapjawRender" + Guid.NewGuid().ToString("N").Substring(0, 8);
        IntPtr desktop = CreateDesktop(name, IntPtr.Zero, IntPtr.Zero, 0, GENERIC_ALL, IntPtr.Zero);
        if (desktop == IntPtr.Zero)
            throw new Exception("CreateDesktop failed: " + Marshal.GetLastWin32Error());
        try
        {
            var si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            si.lpDesktop = name;
            PROCESS_INFORMATION pi;
            var cmd = new StringBuilder("\"" + exe + "\" " + args);
            if (!CreateProcess(exe, cmd, IntPtr.Zero, IntPtr.Zero, false,
                    CREATE_NO_WINDOW | BELOW_NORMAL_PRIORITY_CLASS, IntPtr.Zero, cwd, ref si, out pi))
                throw new Exception("CreateProcess failed: " + Marshal.GetLastWin32Error());
            try
            {
                if (WaitForSingleObject(pi.hProcess, (uint)timeoutMs) == WAIT_TIMEOUT)
                {
                    TerminateProcess(pi.hProcess, 1);
                    WaitForSingleObject(pi.hProcess, 10000);
                    return -1;
                }
                uint code;
                GetExitCodeProcess(pi.hProcess, out code);
                return (int)code;
            }
            finally
            {
                CloseHandle(pi.hThread);
                CloseHandle(pi.hProcess);
            }
        }
        finally
        {
            CloseDesktop(desktop);
        }
    }
}
