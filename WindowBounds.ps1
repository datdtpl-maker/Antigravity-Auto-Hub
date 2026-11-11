if(-not ('HubWindowBounds' -as [type])){
    Add-Type -AssemblyName System.Xaml
    Add-Type -ReferencedAssemblies @([Windows.Window].Assembly.Location,[Windows.Interop.HwndSource].Assembly.Location,[Windows.Point].Assembly.Location,[Windows.Markup.IQueryAmbient].Assembly.Location) -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

public static class HubWindowBounds
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Point { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct Rect { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MinMaxInfo
    {
        public Point Reserved;
        public Point MaxSize;
        public Point MaxPosition;
        public Point MinTrackSize;
        public Point MaxTrackSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo
    {
        public int Size;
        public Rect Monitor;
        public Rect Work;
        public uint Flags;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);

    public static MinMaxInfo Constrain(MinMaxInfo limits, Rect monitor, Rect work)
    {
        limits.MaxPosition.X = work.Left - monitor.Left;
        limits.MaxPosition.Y = work.Top - monitor.Top;
        limits.MaxSize.X = work.Right - work.Left;
        limits.MaxSize.Y = work.Bottom - work.Top;
        return limits;
    }

    public static void Attach(Window window)
    {
        window.SourceInitialized += delegate
        {
            HwndSource source = HwndSource.FromHwnd(new WindowInteropHelper(window).Handle);
            source.AddHook(HandleMessage);
        };
    }

    private static IntPtr HandleMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == 0x0024)
        {
            IntPtr monitor = MonitorFromWindow(window, 2);
            MonitorInfo info = new MonitorInfo();
            info.Size = Marshal.SizeOf(typeof(MonitorInfo));
            if (monitor != IntPtr.Zero && GetMonitorInfo(monitor, ref info))
            {
                MinMaxInfo limits = (MinMaxInfo)Marshal.PtrToStructure(lParam, typeof(MinMaxInfo));
                limits = Constrain(limits, info.Monitor, info.Work);
                Marshal.StructureToPtr(limits, lParam, false);
                handled = true;
            }
        }
        return IntPtr.Zero;
    }
}
'@
}
