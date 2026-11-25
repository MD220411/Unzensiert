// Client of the Unzensiert sandbox (scripts\lib\Sandbox.ps1, docs\security.md "Sandbox").
//
// Unzensiert, as the user, hands one command to the runner (scripts\sandbox\Runner.cs, a service
// that runs as the sandbox account in session 0) through its named pipe and gets the output back.
// Before anything is sent it starts the service when it is stopped (the user may: the rights
// Setup-Sandbox.ps1 gave the service) and checks that the process at the other end of the pipe is
// that service, so a pipe of the same name made by someone else gets nothing. It connects for
// identification only: the service can never act as the user. Closing the pipe (Kill) ends the
// command with everything it started. Built into one DLL with scripts\sandbox\Watch.cs by
// lib\Sandbox.ps1. Keep it ASCII-only and within C# 5.

using System;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace Unzensiert
{
    public sealed class SandboxCommand : IDisposable
    {
        [StructLayout(LayoutKind.Sequential)]
        struct SERVICE_STATUS_PROCESS
        {
            public uint dwServiceType, dwCurrentState, dwControlsAccepted, dwWin32ExitCode, dwServiceSpecificExitCode;
            public uint dwCheckPoint, dwWaitHint, dwProcessId, dwServiceFlags;
        }

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr OpenSCManagerW(string machine, string database, uint access);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr OpenServiceW(IntPtr manager, string name, uint access);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool StartServiceW(IntPtr service, int count, IntPtr arguments);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool QueryServiceStatusEx(IntPtr service, int level, ref SERVICE_STATUS_PROCESS status, int size, out int needed);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool CloseServiceHandle(IntPtr handle);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetNamedPipeServerProcessId(SafePipeHandle pipe, out uint pid);

        const uint SC_MANAGER_CONNECT = 1, SERVICE_QUERY_STATUS = 4, SERVICE_START = 0x10;
        const uint STOPPED = 1, RUNNING = 4;
        const int MaxFrame = 64 << 20;

        readonly MemoryStream output = new MemoryStream();
        readonly MemoryStream errors = new MemoryStream();
        readonly ManualResetEvent exited = new ManualResetEvent(false);
        NamedPipeClientStream pipe;
        Thread reader;
        volatile bool killed;

        // What the command wrote to stdout and stderr, complete once WaitForExit returned true.
        public MemoryStream Output { get { return output; } }
        public MemoryStream Errors { get { return errors; } }
        // Its exit code; 125 when the runner could not run it, -1 when it was stopped (Kill).
        public int ExitCode { get; private set; }

        // The process id of the running service, which is started first when it is stopped. Throws
        // with the reason when it is not set up or does not come up within waitMs.
        public static uint ServiceProcess(string name, int waitMs)
        {
            IntPtr manager = OpenSCManagerW(null, null, SC_MANAGER_CONNECT);
            if (manager == IntPtr.Zero) throw new InvalidOperationException("the service control manager cannot be opened (Windows error " + Marshal.GetLastWin32Error() + ")");
            try
            {
                IntPtr service = OpenServiceW(manager, name, SERVICE_QUERY_STATUS | SERVICE_START);
                if (service == IntPtr.Zero)
                {
                    int e = Marshal.GetLastWin32Error();
                    // 1060: no such service
                    if (e == 1060) throw new InvalidOperationException("the sandbox service is not set up (scripts\\Setup-Sandbox.ps1)");
                    throw new InvalidOperationException("the sandbox service cannot be opened (Windows error " + e + ")");
                }
                try
                {
                    int start = Environment.TickCount;
                    bool started = false;
                    while (true)
                    {
                        var status = new SERVICE_STATUS_PROCESS();
                        int needed;
                        if (!QueryServiceStatusEx(service, 0, ref status, Marshal.SizeOf(typeof(SERVICE_STATUS_PROCESS)), out needed))
                            throw new InvalidOperationException("the state of the sandbox service cannot be read (Windows error " + Marshal.GetLastWin32Error() + ")");
                        if (status.dwCurrentState == RUNNING && status.dwProcessId != 0) return status.dwProcessId;
                        if (status.dwCurrentState == STOPPED)
                        {
                            if (started) throw new InvalidOperationException("the sandbox service ended right after its start (exit code " + status.dwWin32ExitCode + ", " + status.dwServiceSpecificExitCode + ")");
                            // 1056: running already (it was started meanwhile)
                            if (!StartServiceW(service, 0, IntPtr.Zero) && Marshal.GetLastWin32Error() != 1056)
                                throw new InvalidOperationException("the sandbox service does not start (Windows error " + Marshal.GetLastWin32Error() + ")");
                            started = true;
                        }
                        if (Environment.TickCount - start > waitMs) throw new InvalidOperationException("the sandbox service did not come up in time");
                        Thread.Sleep(100);
                    }
                }
                finally { CloseServiceHandle(service); }
            }
            finally { CloseServiceHandle(manager); }
        }

        // Starts a command through the service.
        public static SandboxCommand Start(string service, string pipeName, byte[] request, int waitMs)
        {
            return StartWith(ServiceProcess(service, waitMs), pipeName, request, waitMs);
        }

        // Starts a command through the runner with this process id (a service, or a runner started in
        // the foreground for tests).
        public static SandboxCommand StartWith(uint serverPid, string pipeName, byte[] request, int waitMs)
        {
            var command = new SandboxCommand();
            try
            {
                command.pipe = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.Asynchronous, TokenImpersonationLevel.Identification);
                command.pipe.Connect(waitMs);
                uint pid;
                if (!GetNamedPipeServerProcessId(command.pipe.SafePipeHandle, out pid))
                    throw new InvalidOperationException("the other end of the sandbox pipe cannot be checked (Windows error " + Marshal.GetLastWin32Error() + ")");
                if (pid != serverPid)
                    throw new InvalidOperationException("the sandbox pipe is served by process " + pid + ", not by the sandbox service (" + serverPid + "): nothing was sent");
                var frame = new byte[4 + request.Length];
                BitConverter.GetBytes(request.Length).CopyTo(frame, 0);
                Buffer.BlockCopy(request, 0, frame, 4, request.Length);
                command.pipe.Write(frame, 0, frame.Length);
                command.pipe.Flush();
            }
            catch
            {
                command.Dispose();
                throw;
            }
            command.reader = new Thread(command.Read) { IsBackground = true, Name = "sandbox output" };
            command.reader.Start();
            return command;
        }

        bool ReadFull(byte[] buffer, int count)
        {
            int at = 0;
            while (at < count)
            {
                int n = pipe.Read(buffer, at, count - at);
                if (n <= 0) return false;
                at += n;
            }
            return true;
        }

        void Read()
        {
            bool done = false;
            try
            {
                var head = new byte[5];
                while (!done && ReadFull(head, 5))
                {
                    int length = BitConverter.ToInt32(head, 1);
                    if (length < 0 || length > MaxFrame) break;
                    var data = new byte[length];
                    if (length > 0 && !ReadFull(data, length)) break;
                    switch (head[0])
                    {
                        case 1: output.Write(data, 0, length); break;
                        case 2: errors.Write(data, 0, length); break;
                        case 4:
                            errors.Write(data, 0, length);
                            errors.WriteByte((byte)'\n');
                            break;
                        case 3:
                            ExitCode = length >= 4 ? BitConverter.ToInt32(data, 0) : 125;
                            done = true;
                            break;
                    }
                }
            }
            catch { }
            if (!done)
            {
                ExitCode = killed ? -1 : 125;
                if (!killed)
                {
                    byte[] note = Encoding.UTF8.GetBytes("sandbox: the connection to the sandbox service ended before the command did\n");
                    errors.Write(note, 0, note.Length);
                }
            }
            exited.Set();
        }

        public bool WaitForExit(int milliseconds) { return exited.WaitOne(milliseconds); }

        // Ends the command: the service ends its job when the pipe closes.
        public void Kill()
        {
            killed = true;
            if (pipe != null) try { pipe.Dispose(); } catch { }
            if (reader != null) reader.Join(5000);
        }

        public void Dispose()
        {
            if (pipe != null) try { pipe.Dispose(); } catch { }
        }
    }
}
