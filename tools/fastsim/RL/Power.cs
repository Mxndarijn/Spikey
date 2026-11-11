using System.Runtime.InteropServices;

namespace FastSim.Rl;

/// Windows 11 may run background, below-normal processes in efficiency mode
/// (EcoQoS: slow cores, low clocks). Training opts out, so its threads run
/// at full speed; the priority stays BelowNormal, so the PC stays usable.
public static class Power
{
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_POWER_THROTTLING_STATE
    {
        public uint Version, ControlMask, StateMask;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetProcessInformation(IntPtr process, int infoClass, ref PROCESS_POWER_THROTTLING_STATE info, uint size);

    [DllImport("kernel32.dll")]
    static extern IntPtr GetCurrentProcess();

    const int ProcessPowerThrottling = 4;
    const uint EXECUTION_SPEED = 1, IGNORE_TIMER_RESOLUTION = 4;

    /// Turns power throttling off for this process. False where it isn't supported.
    public static bool full_speed()
    {
        if (!OperatingSystem.IsWindows()) return false;
        try
        {
            var s = new PROCESS_POWER_THROTTLING_STATE { Version = 1, ControlMask = EXECUTION_SPEED | IGNORE_TIMER_RESOLUTION, StateMask = 0 };
            return SetProcessInformation(GetCurrentProcess(), ProcessPowerThrottling, ref s, (uint)Marshal.SizeOf<PROCESS_POWER_THROTTLING_STATE>());
        }
        catch
        {
            return false;
        }
    }
}
