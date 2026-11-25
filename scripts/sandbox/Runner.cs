// Runner of the Unzensiert sandbox (scripts\lib\Sandbox.ps1, docs\security.md "Sandbox").
//
// A Windows service that runs as the sandbox account in a sign-in of its own (session 0). It is set
// up by scripts\Setup-Sandbox.ps1 with one administrator question, Unzensiert starts it when it
// needs it, and it ends itself after a while without commands. The sign-in of its own is the
// point: a process started with CreateProcessWithLogonW carries the logon SID of the user's
// sign-in, and that SID may read and end the user's programs and opens their desktop and named
// objects. Here nothing of the command shares a SID with the user's programs, it sees no desktop
// of the user, and Windows lets every process of session 0 make named objects (Git Bash needs that).
//
// Unzensiert sends a command through a named pipe that only the user who set it up may write to
// (the account itself may only make further instances of it, so neither a command nor anything
// else of the account can send one), and Unzensiert checks that the process at the other end is
// this service. The runner starts the command
// with a restricted copy of its own token:
//   - the groups it is told (Authenticated Users, SERVICE) only count for deny, so what Windows lets
//     every account do on other drives does not apply, and every privilege but bypass-traverse goes;
//   - write-restricted: a write must also be allowed to one of the SID of this project (the project
//     folder has an entry for it, lib\Sandbox.ps1), the account itself (its profile and temp folder;
//     Git Bash makes its pipes with rights for the account only), the logon SID of this sign-in (its
//     window station), Everyone (named objects) or the SID of this run (the processes of the command
//     among themselves). So the command changes no other project folder it was ever let into, and
//     nothing that only "Users" may change (Public, ProgramData). That it owns what it made earlier
//     in another project gives it nothing there either: every project folder has an entry for OWNER
//     RIGHTS that leaves the owner of a file only the right to read its rights (lib\Sandbox.ps1),
//     and the folders it makes are handed to the user after each command (scripts\sandbox\Watch.cs);
//   - in a job object that ends everything the command started, with the user-interface limits;
//   - with nothing but its three standard handles inherited.
// The output comes back through the pipe; when Unzensiert closes it (Esc, time limit), the job ends.
// A folder the command made with rights of its own (Python makes every tempfile.mkdtemp folder for
// its owner, SYSTEM and the administrators only, and pytest its cache so) takes the rights of the
// project folder again afterwards: the user can open and delete it, and a command of another
// project has no right to it through being its owner.
// The runner protects itself: neither the commands nor anything else of the account may open its
// process or its threads (they would get its token, which has none of these limits).
//
//   unzensiert-runner.exe --service --user <SID> [--name <service>]   (as the service control
//                                                                      manager starts it)
//   unzensiert-runner.exe --console --user <SID>    (the same in the foreground, for tests)
//
// Request: int32 length, then UTF-8 fields separated by NUL: "2", groups to disable (SIDs, comma
// separated), program, arguments ("{script}" stands for the script file), extension of the script,
// text of the script, working folder, SID of the project, then any number of NAME=VALUE for the
// environment of the command (on top of the environment of the account).
// Answer: frames of one byte type, int32 length and the data: 1 output, 2 error output, 4 a problem
// of the runner (text), and last 3 the exit code (int32; 125 when the runner could not run it).
// Built by lib\Sandbox.ps1 with the csc.exe of Windows. Keep it ASCII-only and within C# 5.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.ServiceProcess;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

static class Native
{
    public const uint TOKEN_ALL_ACCESS = 0xF01FF, TOKEN_QUERY = 0x8;
    public const uint DISABLE_MAX_PRIVILEGE = 0x1, WRITE_RESTRICTED = 0x8;
    public const uint CREATE_SUSPENDED = 0x4, CREATE_UNICODE_ENVIRONMENT = 0x400, CREATE_NO_WINDOW = 0x08000000;
    public const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
    public const int STARTF_USESTDHANDLES = 0x100;
    public const int JobObjectBasicUIRestrictions = 4, JobObjectExtendedLimitInformation = 9;
    public const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000, JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION = 0x400;
    public const uint INFINITE = 0xFFFFFFFF, HANDLE_FLAG_INHERIT = 1;
    public const int TokenGroups = 2, TokenDefaultDacl = 6, TokenSessionId = 12;
    public const uint SE_GROUP_LOGON_ID = 0xC0000000;
    public const int SE_KERNEL_OBJECT = 6;
    public const uint DACL_SECURITY_INFORMATION = 4, PROTECTED_DACL_SECURITY_INFORMATION = 0x80000000;
    public const uint WRITE_DAC = 0x40000, GENERIC_READ = 0x80000000;
    public const int GENERIC_ALL = 0x10000000, SYNCHRONIZE = 0x100000;
    public const uint PIPE_ACCESS_DUPLEX = 3, FILE_FLAG_OVERLAPPED = 0x40000000, FILE_FLAG_FIRST_PIPE_INSTANCE = 0x00080000;
    public const uint PIPE_REJECT_REMOTE_CLIENTS = 0x8;
    public static readonly IntPtr PROC_THREAD_ATTRIBUTE_HANDLE_LIST = new IntPtr(0x20002);

    [StructLayout(LayoutKind.Sequential)]
    public struct SID_AND_ATTRIBUTES { public IntPtr Sid; public uint Attributes; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO
    {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFOEX { public STARTUPINFO StartupInfo; public IntPtr lpAttributeList; }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

    [StructLayout(LayoutKind.Sequential)]
    public struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public int bInheritHandle; }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit;
        public UIntPtr Affinity; public uint PriorityClass, SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation; public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_UI_RESTRICTIONS { public uint UIRestrictionsClass; }

    [StructLayout(LayoutKind.Sequential)]
    public struct TOKEN_DEFAULT_DACL { public IntPtr DefaultDacl; }

    [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentThread();
    [DllImport("advapi32.dll", SetLastError = true)] public static extern bool OpenProcessToken(IntPtr h, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)] public static extern bool OpenThreadToken(IntPtr thread, uint access, bool openAsSelf, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool CreateRestrictedToken(IntPtr existing, uint flags, uint disableCount, SID_AND_ATTRIBUTES[] disable,
        uint deleteCount, IntPtr deletePrivs, uint restrictCount, SID_AND_ATTRIBUTES[] restrict, out IntPtr newToken);
    [DllImport("advapi32.dll", SetLastError = true)] public static extern bool GetTokenInformation(IntPtr token, int cls, IntPtr info, int len, out int ret);
    [DllImport("advapi32.dll", SetLastError = true)] public static extern bool SetTokenInformation(IntPtr token, int cls, ref TOKEN_DEFAULT_DACL info, int len);
    [DllImport("advapi32.dll", SetLastError = true)] public static extern uint SetSecurityInfo(IntPtr h, int type, uint info, IntPtr owner, IntPtr group, byte[] dacl, IntPtr sacl);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcessAsUserW(IntPtr token, string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit,
        uint flags, IntPtr env, string cwd, ref STARTUPINFOEX si, out PROCESS_INFORMATION pi);
    [DllImport("userenv.dll", SetLastError = true)] public static extern bool CreateEnvironmentBlock(out IntPtr env, IntPtr token, bool inherit);
    [DllImport("userenv.dll", SetLastError = true)] public static extern bool DestroyEnvironmentBlock(IntPtr env);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr CreateJobObjectW(IntPtr attrs, IntPtr name);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetInformationJobObject(IntPtr job, int cls, ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, int len);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetInformationJobObject(IntPtr job, int cls, ref JOBOBJECT_BASIC_UI_RESTRICTIONS info, int len);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool TerminateJobObject(IntPtr job, uint code);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool TerminateProcess(IntPtr process, uint code);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetExitCodeProcess(IntPtr p, out uint code);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool CreatePipe(out IntPtr read, out IntPtr write, ref SECURITY_ATTRIBUTES sa, int size);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetHandleInformation(IntPtr h, uint mask, uint flags);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateFileW(string name, uint access, uint share, ref SECURITY_ATTRIBUTES sa, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr OpenThread(uint access, bool inherit, uint id);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returnSize);
    [DllImport("kernel32.dll")] public static extern void DeleteProcThreadAttributeList(IntPtr list);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateNamedPipeW(string name, uint openMode, uint pipeMode, uint maxInstances, uint outSize, uint inSize, uint timeout, ref SECURITY_ATTRIBUTES sa);
    public static string Error(string what) { return what + " failed (Windows error " + Marshal.GetLastWin32Error() + ")"; }
}

// One SID as Windows wants it, freed with the list it belongs to.
sealed class SidList : IDisposable
{
    readonly List<IntPtr> memory = new List<IntPtr>();
    public readonly List<Native.SID_AND_ATTRIBUTES> Items = new List<Native.SID_AND_ATTRIBUTES>();
    public void Add(SecurityIdentifier sid)
    {
        byte[] bytes = new byte[sid.BinaryLength];
        sid.GetBinaryForm(bytes, 0);
        IntPtr p = Marshal.AllocHGlobal(bytes.Length);
        Marshal.Copy(bytes, 0, p, bytes.Length);
        memory.Add(p);
        Items.Add(new Native.SID_AND_ATTRIBUTES { Sid = p, Attributes = 0 });
    }
    public Native.SID_AND_ATTRIBUTES[] ToArray() { return Items.Count > 0 ? Items.ToArray() : null; }
    public void Dispose() { foreach (IntPtr p in memory) Marshal.FreeHGlobal(p); memory.Clear(); }
}

// Frames to Unzensiert; a closed pipe (Unzensiert stopped the command) is not an error here.
sealed class FrameWriter
{
    readonly Stream pipe;
    readonly object gate = new object();
    public FrameWriter(Stream pipe) { this.pipe = pipe; }
    public void Bytes(byte type, byte[] data, int count)
    {
        var frame = new byte[5 + count];
        frame[0] = type;
        BitConverter.GetBytes(count).CopyTo(frame, 1);
        Buffer.BlockCopy(data, 0, frame, 5, count);
        lock (gate) { try { pipe.Write(frame, 0, frame.Length); } catch { } }
    }
    public void Text(byte type, string text) { byte[] b = Encoding.UTF8.GetBytes(text); Bytes(type, b, b.Length); }
    public void Int(byte type, int value) { byte[] b = BitConverter.GetBytes(value); Bytes(type, b, b.Length); }
}

// The folders a command makes in its project folder (seen by a watcher while it runs). Afterwards
// those of this account with rights of their own (a protected list, as Python gives a folder made
// with mode 0o700) take the rights of the folder they are in again. This runs as the account, which
// owns them, so a folder swapped meanwhile can only be one the account may change anyway.
sealed class MadeFolders : IDisposable
{
    readonly string root;
    readonly HashSet<string> paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    readonly FileSystemWatcher watcher;
    volatile bool overflow;

    public MadeFolders(string root)
    {
        this.root = root;
        try
        {
            watcher = new FileSystemWatcher(root) { IncludeSubdirectories = true, InternalBufferSize = 65536, NotifyFilter = NotifyFilters.DirectoryName };
            watcher.Created += (s, e) => { lock (paths) paths.Add(e.FullPath); };
            watcher.Renamed += (s, e) => { lock (paths) paths.Add(e.FullPath); };
            watcher.Error += (s, e) => { overflow = true; };
            watcher.EnableRaisingEvents = true;
        }
        catch { overflow = true; }
    }

    public void Finish(SecurityIdentifier account)
    {
        if (watcher != null) watcher.EnableRaisingEvents = false;
        var todo = new List<string>();
        if (overflow)
        {
            // too many at once: every folder below, without following links
            var stack = new Stack<string>();
            stack.Push(root);
            while (stack.Count > 0)
            {
                string dir = stack.Pop();
                try
                {
                    foreach (string sub in Directory.EnumerateDirectories(dir))
                    {
                        if ((File.GetAttributes(sub) & FileAttributes.ReparsePoint) != 0) continue;
                        todo.Add(sub);
                        stack.Push(sub);
                    }
                }
                catch { }
            }
        }
        else lock (paths) todo.AddRange(paths);
        foreach (string path in todo)
        {
            try
            {
                if (!Directory.Exists(path) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) continue;
                DirectorySecurity ds = Directory.GetAccessControl(path, AccessControlSections.Access | AccessControlSections.Owner);
                if (!ds.AreAccessRulesProtected || !account.Equals(ds.GetOwner(typeof(SecurityIdentifier)))) continue;
                // no entries of its own, and those of the folder above passed on again
                var fresh = new DirectorySecurity();
                fresh.SetAccessRuleProtection(false, false);
                Directory.SetAccessControl(path, fresh);
            }
            catch { }
        }
    }

    public void Dispose() { if (watcher != null) watcher.Dispose(); }
}

// The job of one command; closed once, and never used after (its number may belong to another job).
sealed class JobState
{
    public IntPtr Handle;
    public void Terminate(uint code) { lock (this) { if (Handle != IntPtr.Zero) Native.TerminateJobObject(Handle, code); } }
    public void Close() { lock (this) { if (Handle != IntPtr.Zero) { Native.CloseHandle(Handle); Handle = IntPtr.Zero; } } }
}

sealed class Broker
{
    // the SIDs the runner makes up: only these may come as the SID of a project (lib\Sandbox.ps1
    // makes them from the path of the folder), never a real account or group
    public const string ProjectPrefix = "S-1-9-1101-1-";
    const string RunPrefix = "S-1-9-1101-3-";
    const int MaxRequest = 16 << 20;
    const int IdleMinutes = 20;

    readonly SecurityIdentifier user;
    readonly SecurityIdentifier account;
    readonly SecurityIdentifier logon;
    readonly string pipeName;
    readonly object gate = new object();
    readonly HashSet<JobState> jobs = new HashSet<JobState>();
    readonly Random random = new Random();
    volatile bool stopping;
    int active;
    DateTime lastUse = DateTime.UtcNow;
    Thread listener;
    Timer idleTimer;
    NamedPipeServerStream first;
    public Action OnIdle;

    public Broker(SecurityIdentifier user)
    {
        this.user = user;
        account = WindowsIdentity.GetCurrent().User;
        logon = LogonSid();
        pipeName = "unzensiert-sandbox-" + user.Value;
    }

    static SecurityIdentifier LogonSid()
    {
        IntPtr token;
        if (!Native.OpenProcessToken(Native.GetCurrentProcess(), Native.TOKEN_QUERY, out token)) return null;
        try
        {
            int len;
            Native.GetTokenInformation(token, Native.TokenGroups, IntPtr.Zero, 0, out len);
            IntPtr buf = Marshal.AllocHGlobal(len);
            try
            {
                if (!Native.GetTokenInformation(token, Native.TokenGroups, buf, len, out len)) return null;
                int count = Marshal.ReadInt32(buf);
                int size = Marshal.SizeOf(typeof(Native.SID_AND_ATTRIBUTES));
                for (int i = 0; i < count; i++)
                {
                    var g = (Native.SID_AND_ATTRIBUTES)Marshal.PtrToStructure(new IntPtr(buf.ToInt64() + IntPtr.Size + i * size), typeof(Native.SID_AND_ATTRIBUTES));
                    if ((g.Attributes & Native.SE_GROUP_LOGON_ID) == Native.SE_GROUP_LOGON_ID) return new SecurityIdentifier(g.Sid);
                }
                return null;
            }
            finally { Marshal.FreeHGlobal(buf); }
        }
        finally { Native.CloseHandle(token); }
    }

    static RawAcl MakeAcl(SecurityIdentifier[] sids, int[] masks)
    {
        var acl = new RawAcl(GenericAcl.AclRevision, sids.Length);
        for (int i = 0; i < sids.Length; i++)
            acl.InsertAce(acl.Count, new CommonAce(AceFlags.None, AceQualifier.AccessAllowed, masks[i], sids[i], false, null));
        return acl;
    }

    static byte[] AclBytes(RawAcl acl) { var b = new byte[acl.BinaryLength]; acl.GetBinaryForm(b, 0); return b; }

    static bool SetDefaultDacl(IntPtr token, RawAcl acl)
    {
        byte[] b = AclBytes(acl);
        IntPtr p = Marshal.AllocHGlobal(b.Length);
        try
        {
            Marshal.Copy(b, 0, p, b.Length);
            var d = new Native.TOKEN_DEFAULT_DACL { DefaultDacl = p };
            return Native.SetTokenInformation(token, Native.TokenDefaultDacl, ref d, Marshal.SizeOf(typeof(Native.TOKEN_DEFAULT_DACL)));
        }
        finally { Marshal.FreeHGlobal(p); }
    }

    // Nothing of this account may open the runner's process or threads (they would get its token):
    // SYSTEM only, and the owner (this same account) loses what Windows gives an owner by itself
    // (OWNER RIGHTS). New threads and objects without rights of their own get the same.
    public string Protect()
    {
        var guard = MakeAcl(new[] { new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), new SecurityIdentifier("S-1-3-4") },
                            new[] { Native.GENERIC_ALL, Native.SYNCHRONIZE });
        IntPtr own;
        if (!Native.OpenProcessToken(Native.GetCurrentProcess(), Native.TOKEN_ALL_ACCESS, out own)) return Native.Error("OpenProcessToken");
        try { if (!SetDefaultDacl(own, guard)) return Native.Error("protecting the default rights"); }
        finally { Native.CloseHandle(own); }
        byte[] g = AclBytes(guard);
        uint info = Native.DACL_SECURITY_INFORMATION | Native.PROTECTED_DACL_SECURITY_INFORMATION;
        uint e = Native.SetSecurityInfo(Native.GetCurrentProcess(), Native.SE_KERNEL_OBJECT, info, IntPtr.Zero, IntPtr.Zero, g, IntPtr.Zero);
        if (e != 0) return "protecting the process failed (Windows error " + e + ")";
        foreach (ProcessThread t in Process.GetCurrentProcess().Threads)
        {
            IntPtr h = Native.OpenThread(Native.WRITE_DAC, false, (uint)t.Id);
            if (h == IntPtr.Zero) continue;
            Native.SetSecurityInfo(h, Native.SE_KERNEL_OBJECT, info, IntPtr.Zero, IntPtr.Zero, g, IntPtr.Zero);
            Native.CloseHandle(h);
        }
        return "";
    }

    // Entries that trials of 2026-11-24 left on the profile and the registry of the account go (they
    // let a made-up SID change all of it).
    static readonly string[] OldSids = { "S-1-9-1000-100", "S-1-9-1101-2-1" };

    public void CleanHome()
    {
        try
        {
            string profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            if (!string.IsNullOrEmpty(profile))
            {
                var di = new DirectoryInfo(profile);
                DirectorySecurity ds = di.GetAccessControl(AccessControlSections.Access);
                bool changed = false;
                foreach (string sid in OldSids)
                    foreach (FileSystemAccessRule r in ds.GetAccessRules(true, false, typeof(SecurityIdentifier)))
                        if (r.IdentityReference.Value == sid) { ds.PurgeAccessRules(new SecurityIdentifier(sid)); changed = true; break; }
                if (changed) di.SetAccessControl(ds);
            }
        }
        catch { }
        try
        {
            using (Microsoft.Win32.RegistryKey key = Microsoft.Win32.Registry.Users.OpenSubKey(account.Value,
                Microsoft.Win32.RegistryKeyPermissionCheck.ReadWriteSubTree, RegistryRights.ReadPermissions | RegistryRights.ChangePermissions))
            {
                if (key == null) return;
                RegistrySecurity rs = key.GetAccessControl(AccessControlSections.Access);
                bool changed = false;
                foreach (string sid in OldSids)
                    foreach (RegistryAccessRule r in rs.GetAccessRules(true, false, typeof(SecurityIdentifier)))
                        if (r.IdentityReference.Value == sid) { rs.PurgeAccessRules(new SecurityIdentifier(sid)); changed = true; break; }
                if (changed) key.SetAccessControl(rs);
            }
        }
        catch { }
    }

    // ---------- the pipe ----------

    NamedPipeServerStream MakePipe(bool isFirst)
    {
        // the user may read and write (send commands); this account may only make further instances
        // (0x4) and look at the rights (READ_CONTROL, SYNCHRONIZE), not write: so neither a command
        // nor anything else of the account can send a command; SYSTEM for the system
        var sd = new RawSecurityDescriptor("D:P(A;;GRGW;;;" + user.Value + ")(A;;0x120004;;;" + account.Value + ")(A;;GA;;;SY)");
        var bytes = new byte[sd.BinaryLength];
        sd.GetBinaryForm(bytes, 0);
        GCHandle pin = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        try
        {
            var sa = new Native.SECURITY_ATTRIBUTES { nLength = Marshal.SizeOf(typeof(Native.SECURITY_ATTRIBUTES)), lpSecurityDescriptor = pin.AddrOfPinnedObject(), bInheritHandle = 0 };
            uint mode = Native.PIPE_ACCESS_DUPLEX | Native.FILE_FLAG_OVERLAPPED | (isFirst ? Native.FILE_FLAG_FIRST_PIPE_INSTANCE : 0);
            IntPtr h = Native.CreateNamedPipeW(@"\\.\pipe\" + pipeName, mode, Native.PIPE_REJECT_REMOTE_CLIENTS, 16, 65536, 65536, 0, ref sa);
            if (h == new IntPtr(-1)) throw new IOException(Native.Error(isFirst ? "making the pipe (someone else has its name?)" : "making the pipe"));
            return new NamedPipeServerStream(PipeDirection.InOut, true, false, new SafePipeHandle(h, true));
        }
        finally { pin.Free(); }
    }

    // Makes the first instance of the pipe (a name someone else holds already fails here) and listens.
    public void Start()
    {
        first = MakePipe(true);
        listener = new Thread(Listen) { IsBackground = true, Name = "listener" };
        listener.Start();
        idleTimer = new Timer(_ =>
        {
            if (OnIdle == null || stopping) return;
            if (Thread.VolatileRead(ref active) == 0 && DateTime.UtcNow - lastUse > TimeSpan.FromMinutes(IdleMinutes)) OnIdle();
        }, null, 60000, 60000);
    }

    public void Stop()
    {
        stopping = true;
        lock (gate) { foreach (JobState job in jobs) job.Terminate(1); }
    }

    void Listen()
    {
        NamedPipeServerStream pipe = first;
        while (!stopping)
        {
            try
            {
                if (pipe == null) pipe = MakePipe(false);
                pipe.WaitForConnection();
            }
            catch
            {
                if (pipe != null) pipe.Dispose();
                pipe = null;
                if (stopping) return;
                Thread.Sleep(200);
                continue;
            }
            var served = pipe;
            pipe = null;
            lastUse = DateTime.UtcNow;
            Interlocked.Increment(ref active);
            var t = new Thread(() =>
            {
                try { Serve(served); }
                catch { }
                finally { served.Dispose(); Interlocked.Decrement(ref active); lastUse = DateTime.UtcNow; }
            }) { IsBackground = true };
            t.Start();
        }
    }

    static byte[] ReadExactly(Stream s, int count)
    {
        var buf = new byte[count];
        int at = 0;
        while (at < count)
        {
            int n = s.Read(buf, at, count - at);
            if (n <= 0) return null;
            at += n;
        }
        return buf;
    }

    // One connection: only the user can have opened it for writing (the rights of the pipe).
    void Serve(NamedPipeServerStream pipe)
    {
        byte[] head = ReadExactly(pipe, 4);
        if (head == null) return;
        int length = BitConverter.ToInt32(head, 0);
        if (length <= 0 || length > MaxRequest) return;
        byte[] body = ReadExactly(pipe, length);
        if (body == null) return;
        var writer = new FrameWriter(pipe);
        int code;
        try { code = Run(Encoding.UTF8.GetString(body).Split('\0'), pipe, writer); }
        catch (Exception e) { writer.Text(4, "sandbox runner: " + e.Message); code = 125; }
        writer.Int(3, code);
        try { pipe.Flush(); pipe.WaitForPipeDrain(); } catch { }
    }

    // ---------- one command ----------

    int Run(string[] f, Stream pipe, FrameWriter writer)
    {
        if (f.Length < 8 || f[0] != "2") throw new InvalidDataException("unknown request");
        string program = f[2], arguments = f[3], extension = f[4], text = f[5], cwd = f[6];
        if (!f[7].StartsWith(ProjectPrefix, StringComparison.Ordinal)) throw new InvalidDataException("not the SID of a project: " + f[7]);
        var project = new SecurityIdentifier(f[7]);
        if (!Directory.Exists(cwd)) throw new InvalidDataException("the working folder is not there: " + cwd);
        SecurityIdentifier run;
        lock (random) run = new SecurityIdentifier(RunPrefix + random.Next(1, int.MaxValue));

        IntPtr own = IntPtr.Zero, token = IntPtr.Zero, env = IntPtr.Zero, list = IntPtr.Zero, handles = IntPtr.Zero;
        var job = new JobState();
        MadeFolders made = null;
        IntPtr outRead = IntPtr.Zero, outWrite = IntPtr.Zero, errRead = IntPtr.Zero, errWrite = IntPtr.Zero, nul = IntPtr.Zero;
        var pi = new Native.PROCESS_INFORMATION();
        string script = null;
        var disable = new SidList();
        var restrict = new SidList();
        try
        {
            if (!Native.OpenProcessToken(Native.GetCurrentProcess(), Native.TOKEN_ALL_ACCESS, out own)) throw new IOException(Native.Error("OpenProcessToken"));
            foreach (string sid in f[1].Split(','))
                if (sid.Trim().Length > 0) disable.Add(new SecurityIdentifier(sid.Trim()));
            restrict.Add(project);
            // the account itself: its profile and temp folder, and Git Bash (cygwin) makes its pipes
            // and objects with rights for the account only and opens them again
            restrict.Add(account);
            if (logon != null) restrict.Add(logon);
            restrict.Add(new SecurityIdentifier(WellKnownSidType.WorldSid, null));
            restrict.Add(run);
            if (!Native.CreateRestrictedToken(own, Native.DISABLE_MAX_PRIVILEGE | Native.WRITE_RESTRICTED, (uint)disable.Items.Count, disable.ToArray(),
                    0, IntPtr.Zero, (uint)restrict.Items.Count, restrict.ToArray(), out token)) throw new IOException(Native.Error("CreateRestrictedToken"));
            // what the command makes without rights of its own (its processes, threads, named objects):
            // the account and SYSTEM, and the SID of this run so its processes may end each other
            var system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
            if (!SetDefaultDacl(token, MakeAcl(new[] { account, system, run }, new[] { Native.GENERIC_ALL, Native.GENERIC_ALL, Native.GENERIC_ALL })))
                throw new IOException(Native.Error("default rights of the command"));

            // the environment of the account, then what Unzensiert sends
            if (!Native.CreateEnvironmentBlock(out env, token, false)) throw new IOException(Native.Error("CreateEnvironmentBlock"));
            var vars = ReadEnvironment(env);
            for (int i = 8; i < f.Length; i++)
            {
                int at = f[i].IndexOf('=');
                if (at > 0) vars[f[i].Substring(0, at)] = f[i].Substring(at + 1);
            }
            string temp;
            if (!vars.TryGetValue("TEMP", out temp) || !Directory.Exists(temp)) temp = Path.GetTempPath();
            if (text.Length > 0)
            {
                script = Path.Combine(temp, "unzensiert-" + Guid.NewGuid().ToString("N").Substring(0, 10) + extension);
                File.WriteAllText(script, text, new UTF8Encoding(extension.Equals(".ps1", StringComparison.OrdinalIgnoreCase)));
            }
            byte[] block = MakeEnvironment(vars);

            // its standard handles: two pipes and NUL, the only handles it inherits. The pipes get rights
            // of their own: CreatePipe opens the second end by name, which the protected default
            // rights of the runner (Protect) would refuse it
            var pipeSd = new RawSecurityDescriptor("D:P(A;;GA;;;SY)(A;;GA;;;" + account.Value + ")");
            var pipeSdBytes = new byte[pipeSd.BinaryLength];
            pipeSd.GetBinaryForm(pipeSdBytes, 0);
            GCHandle sdPin = GCHandle.Alloc(pipeSdBytes, GCHandleType.Pinned);
            var inherit = new Native.SECURITY_ATTRIBUTES { nLength = Marshal.SizeOf(typeof(Native.SECURITY_ATTRIBUTES)), lpSecurityDescriptor = sdPin.AddrOfPinnedObject(), bInheritHandle = 1 };
            try
            {
                if (!Native.CreatePipe(out outRead, out outWrite, ref inherit, 0) || !Native.CreatePipe(out errRead, out errWrite, ref inherit, 0))
                    throw new IOException(Native.Error("CreatePipe"));
            }
            finally { sdPin.Free(); }
            inherit.lpSecurityDescriptor = IntPtr.Zero;
            Native.SetHandleInformation(outRead, Native.HANDLE_FLAG_INHERIT, 0);
            Native.SetHandleInformation(errRead, Native.HANDLE_FLAG_INHERIT, 0);
            nul = Native.CreateFileW("NUL", Native.GENERIC_READ, 3, ref inherit, 3, 0, IntPtr.Zero);
            if (nul == new IntPtr(-1)) { nul = IntPtr.Zero; throw new IOException(Native.Error("opening NUL")); }
            IntPtr size = IntPtr.Zero;
            Native.InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
            list = Marshal.AllocHGlobal(size);
            if (!Native.InitializeProcThreadAttributeList(list, 1, 0, ref size)) { Marshal.FreeHGlobal(list); list = IntPtr.Zero; throw new IOException(Native.Error("InitializeProcThreadAttributeList")); }
            handles = Marshal.AllocHGlobal(3 * IntPtr.Size);
            Marshal.WriteIntPtr(handles, 0, nul);
            Marshal.WriteIntPtr(handles, IntPtr.Size, outWrite);
            Marshal.WriteIntPtr(handles, 2 * IntPtr.Size, errWrite);
            if (!Native.UpdateProcThreadAttribute(list, 0, Native.PROC_THREAD_ATTRIBUTE_HANDLE_LIST, handles, new IntPtr(3 * IntPtr.Size), IntPtr.Zero, IntPtr.Zero))
                throw new IOException(Native.Error("UpdateProcThreadAttribute"));

            // everything it starts lives in one job, which ends with the command or when Unzensiert
            // closes the pipe
            job.Handle = Native.CreateJobObjectW(IntPtr.Zero, IntPtr.Zero);
            if (job.Handle == IntPtr.Zero) throw new IOException(Native.Error("CreateJobObject"));
            var limits = new Native.JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            limits.BasicLimitInformation.LimitFlags = Native.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | Native.JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION;
            if (!Native.SetInformationJobObject(job.Handle, Native.JobObjectExtendedLimitInformation, ref limits, Marshal.SizeOf(typeof(Native.JOBOBJECT_EXTENDED_LIMIT_INFORMATION))))
                throw new IOException(Native.Error("SetInformationJobObject"));
            var ui = new Native.JOBOBJECT_BASIC_UI_RESTRICTIONS { UIRestrictionsClass = 0xFF };
            if (!Native.SetInformationJobObject(job.Handle, Native.JobObjectBasicUIRestrictions, ref ui, 4)) throw new IOException(Native.Error("job UI limits"));
            lock (gate) jobs.Add(job);

            var si = new Native.STARTUPINFOEX();
            si.StartupInfo.cb = Marshal.SizeOf(typeof(Native.STARTUPINFOEX));
            si.StartupInfo.dwFlags = Native.STARTF_USESTDHANDLES;
            si.StartupInfo.hStdInput = nul;
            si.StartupInfo.hStdOutput = outWrite;
            si.StartupInfo.hStdError = errWrite;
            si.lpAttributeList = list;
            string commandLine = "\"" + program + "\"";
            if (arguments.Length > 0) commandLine += " " + (script == null ? arguments : arguments.Replace("{script}", script));
            var line = new StringBuilder(commandLine, commandLine.Length + 1);
            // the folders it makes, to give them the rights of the project again afterwards
            made = new MadeFolders(cwd);
            GCHandle envPin = GCHandle.Alloc(block, GCHandleType.Pinned);
            try
            {
                if (!Native.CreateProcessAsUserW(token, null, line, IntPtr.Zero, IntPtr.Zero, true,
                        Native.CREATE_SUSPENDED | Native.CREATE_NO_WINDOW | Native.CREATE_UNICODE_ENVIRONMENT | Native.EXTENDED_STARTUPINFO_PRESENT,
                        envPin.AddrOfPinnedObject(), cwd, ref si, out pi)) throw new IOException(Native.Error("starting " + program));
            }
            finally { envPin.Free(); }
            if (!Native.AssignProcessToJobObject(job.Handle, pi.hProcess))
            {
                // without the job its children could outlive a stop: better not run it at all
                Native.TerminateProcess(pi.hProcess, 125);
                throw new IOException(Native.Error("AssignProcessToJobObject"));
            }
            // the ends of the command are its own now: the output ends when the last one closes them
            Native.CloseHandle(outWrite); outWrite = IntPtr.Zero;
            Native.CloseHandle(errWrite); errWrite = IntPtr.Zero;
            Native.CloseHandle(nul); nul = IntPtr.Zero;
            Native.ResumeThread(pi.hThread);

            Thread o = Relay(outRead, 1, writer);
            Thread e = Relay(errRead, 2, writer);
            outRead = IntPtr.Zero; errRead = IntPtr.Zero;
            // Unzensiert never writes again: a read that ends means it closed the pipe (a stop)
            var watchStop = new Thread(() =>
            {
                try { var one = new byte[1]; pipe.Read(one, 0, 1); } catch { }
                job.Terminate(1);
            }) { IsBackground = true };
            watchStop.Start();
            Native.WaitForSingleObject(pi.hProcess, Native.INFINITE);
            uint code;
            Native.GetExitCodeProcess(pi.hProcess, out code);
            // what it left running in the background ends with it, as in a terminal window that closes
            job.Terminate(code);
            o.Join(10000);
            e.Join(10000);
            made.Finish(account);
            return (int)code;
        }
        finally
        {
            if (made != null) made.Dispose();
            disable.Dispose();
            restrict.Dispose();
            lock (gate) jobs.Remove(job);
            job.Close();
            if (pi.hProcess != IntPtr.Zero) Native.CloseHandle(pi.hProcess);
            if (pi.hThread != IntPtr.Zero) Native.CloseHandle(pi.hThread);
            foreach (IntPtr h in new[] { outRead, outWrite, errRead, errWrite, nul, token, own })
                if (h != IntPtr.Zero) Native.CloseHandle(h);
            if (list != IntPtr.Zero) { Native.DeleteProcThreadAttributeList(list); Marshal.FreeHGlobal(list); }
            if (handles != IntPtr.Zero) Marshal.FreeHGlobal(handles);
            if (env != IntPtr.Zero) Native.DestroyEnvironmentBlock(env);
            if (script != null) try { File.Delete(script); } catch { }
        }
    }

    static Thread Relay(IntPtr read, byte type, FrameWriter writer)
    {
        var t = new Thread(() =>
        {
            using (var s = new FileStream(new SafeFileHandle(read, true), FileAccess.Read, 4096, false))
            {
                var buf = new byte[32768];
                int n;
                try { while ((n = s.Read(buf, 0, buf.Length)) > 0) writer.Bytes(type, buf, n); } catch { }
            }
        }) { IsBackground = true };
        t.Start();
        return t;
    }

    static Dictionary<string, string> ReadEnvironment(IntPtr block)
    {
        var vars = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        IntPtr p = block;
        while (true)
        {
            string entry = Marshal.PtrToStringUni(p);
            if (string.IsNullOrEmpty(entry)) break;
            int at = entry.IndexOf('=', 1);
            if (at > 0) vars[entry.Substring(0, at)] = entry.Substring(at + 1);
            p = new IntPtr(p.ToInt64() + (entry.Length + 1) * 2);
        }
        return vars;
    }

    static byte[] MakeEnvironment(Dictionary<string, string> vars)
    {
        var names = new List<string>(vars.Keys);
        names.Sort(StringComparer.OrdinalIgnoreCase);
        var sb = new StringBuilder();
        foreach (string n in names) sb.Append(n).Append('=').Append(vars[n]).Append('\0');
        sb.Append('\0');
        return Encoding.Unicode.GetBytes(sb.ToString());
    }
}

sealed class RunnerService : ServiceBase
{
    readonly Broker broker;
    public RunnerService(Broker broker, string name)
    {
        this.broker = broker;
        ServiceName = name;
        CanStop = true;
        broker.OnIdle = () => { try { Stop(); } catch { } };
    }
    protected override void OnStart(string[] args) { broker.Start(); }
    protected override void OnStop() { broker.Stop(); }
}

static class Program
{
    static int Main(string[] args)
    {
        string mode = "", user = "", name = "UnzensiertSandbox";
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--service" || args[i] == "--console") mode = args[i];
            else if (args[i] == "--user" && i + 1 < args.Length) user = args[++i];
            else if (args[i] == "--name" && i + 1 < args.Length) name = args[++i];
        }
        if (mode.Length == 0 || user.Length == 0)
        {
            Console.Error.WriteLine("usage: unzensiert-runner.exe --service|--console --user <SID>");
            return 2;
        }
        var broker = new Broker(new SecurityIdentifier(user));
        string problem = broker.Protect();
        broker.CleanHome();
        if (problem.Length > 0)
        {
            // a runner that cannot protect itself does not serve anything
            Console.Error.WriteLine("sandbox runner: " + problem);
            return 1;
        }
        if (mode == "--service")
        {
            ServiceBase.Run(new RunnerService(broker, name));
            return 0;
        }
        broker.Start();
        Console.Out.WriteLine("listening");
        Console.Out.Flush();
        Thread.Sleep(Timeout.Infinite);
        return 0;
    }
}
