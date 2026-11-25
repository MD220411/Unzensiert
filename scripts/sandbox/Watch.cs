// Watch of the Unzensiert sandbox (scripts\lib\Sandbox.ps1, docs\security.md "Sandbox").
//
// A command in the sandbox may change the project folder, but some files of a project run later as
// the user, outside the sandbox: git reads .git (config, hooks, commondir) at every git status of
// the user or of an editor, editors obey .vscode and the like, Explorer opens shortcuts. Around
// every command of the sandbox Unzensiert (as the user) does this:
//
//   Prepare  the repositories of the project that the sandbox account does not own become read-only
//            for its group (one inheritable deny entry on the git folder, so what git makes later
//            inherits it), and so do the protected files and folders that exist ("protectedFiles"
//            in config\guard.json); the folders between the project folder and such a path may not
//            be renamed by the group, so nothing can take its place; what the account made there
//            earlier goes. Paths and file ids are remembered.
//   Start    a FileSystemWatcher reacts at once when a .git or a protected name appears, or a folder
//            (which may bring one along): made by the sandbox account, it goes (a folder that is not
//            empty is renamed to <name>.blocked-by-sandbox; a repository of the account stays, git
//            refuses it for the user); protected before and moved along with a folder above it, it
//            stays protected; a link, or something of the user the sandbox could change and moved
//            there (renamed folders keep their owner, and git trusts what the user owns), is
//            renamed to <name>.blocked-by-sandbox and Violation tells Unzensiert to end the command.
//   Finish   the watcher stops and the same check runs over the whole folder once more, for what the
//            watcher may have missed; the processes of the command have ended by then. The folders
//            the command made go to the user (not a .git), so the account has no rights of an owner
//            on them in a command of another project.
//
// The command runs while the watch acts, and it may rename folders and make links in the project:
// so the watch opens what it judges once, without following a link at its end, checks that the open
// object is really at that place (no link on the way), and judges, deletes and renames through that
// handle only, never again by name. Renaming keeps the object in the folder it is in.
//
// The deny entries name only the group of the sandbox: the user, the editors and git as the user
// are not touched. Built by lib\Sandbox.ps1 with the csc.exe of Windows into a DLL next to the
// runner. Keep it ASCII-only and within C# 5 (the compiler of .NET Framework 4).

using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

namespace Unzensiert
{
    public sealed class SandboxWatch : IDisposable
    {
        // what the group may not do: write, append, attributes, delete, delete inside, rights, owner
        // (no SYNCHRONIZE and no READ_CONTROL: a deny of those would stop reading as well)
        const FileSystemRights DenyFile = FileSystemRights.WriteData | FileSystemRights.AppendData |
            FileSystemRights.WriteExtendedAttributes | FileSystemRights.WriteAttributes | FileSystemRights.Delete |
            FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;
        const FileSystemRights DenyFolder = DenyFile | FileSystemRights.DeleteSubdirectoriesAndFiles;
        const int MaxNotes = 20;

        // ---------- Windows ----------

        const uint DELETE = 0x10000, READ_CONTROL = 0x20000, WRITE_DAC = 0x40000, SYNCHRONIZE = 0x100000, FILE_READ_ATTRIBUTES = 0x80;
        const uint SHARE_ALL = 7, OPEN_EXISTING = 3;
        const uint FLAG_BACKUP_SEMANTICS = 0x02000000, FLAG_OPEN_REPARSE_POINT = 0x00200000;
        const int SE_FILE_OBJECT = 1;
        const uint OWNER_SECURITY_INFORMATION = 1, DACL_SECURITY_INFORMATION = 4;
        const int FileDispositionInfo = 4, FileRenameInformation = 10;
        const int ERROR_SHARING_VIOLATION = 32;

        [StructLayout(LayoutKind.Sequential)]
        struct BY_HANDLE_FILE_INFORMATION
        {
            public uint FileAttributes, CreationLow, CreationHigh, AccessLow, AccessHigh, WriteLow, WriteHigh;
            public uint VolumeSerialNumber, FileSizeHigh, FileSizeLow, NumberOfLinks, FileIndexHigh, FileIndexLow;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct IO_STATUS_BLOCK { public IntPtr Status; public IntPtr Information; }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sa, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern uint GetFinalPathNameByHandleW(SafeFileHandle h, StringBuilder path, uint size, uint flags);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetFileInformationByHandle(SafeFileHandle h, out BY_HANDLE_FILE_INFORMATION info);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetFileInformationByHandle(SafeFileHandle h, int cls, byte[] info, uint size);
        [DllImport("ntdll.dll")]
        static extern int NtSetInformationFile(SafeFileHandle h, out IO_STATUS_BLOCK io, byte[] info, int length, int cls);
        [DllImport("advapi32.dll")]
        static extern uint GetSecurityInfo(SafeFileHandle h, int type, uint info, out IntPtr owner, out IntPtr group, out IntPtr dacl, out IntPtr sacl, out IntPtr descriptor);
        [DllImport("advapi32.dll")]
        static extern uint GetSecurityDescriptorLength(IntPtr descriptor);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool SetFileSecurityW(string name, uint info, byte[] descriptor);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool SetKernelObjectSecurity(SafeFileHandle h, uint info, byte[] descriptor);
        [DllImport("kernel32.dll")]
        static extern IntPtr LocalFree(IntPtr p);

        // ---------- state ----------

        readonly string root;
        readonly int rootLength;
        readonly string rootFinal;
        readonly Regex files;
        readonly Regex folders;
        // the last part of every pattern, for a quick look at a name before the patterns themselves
        readonly HashSet<string> names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        readonly Regex nameWildcards;
        readonly HashSet<string> skip;
        readonly SecurityIdentifier group;
        readonly SecurityIdentifier account;
        readonly object gate = new object();
        // protected paths of before the command, with the id of the object that was there
        readonly Dictionary<string, string> before = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        // of those, the ones whose folders up to the project folder the group may not rename
        // (KeepInPlace): only the user can put something new there
        readonly HashSet<string> fixedPlaces = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        readonly List<string> notes = new List<string>();
        int moreNotes;
        FileSystemWatcher watcher;
        volatile bool violation;

        // Something not made by the sandbox was moved to a place that runs outside it: end the command.
        public bool Violation { get { return violation; } }
        // Protected paths and repositories found by Prepare, and how long Prepare took.
        public int Protected { get { return before.Count; } }
        public double PrepareMilliseconds { get; private set; }

        // folders that appeared while the command ran (made or moved in), and whether the watcher
        // lost count; Finish gives those of the account to the user
        readonly HashSet<string> madeFolders = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        volatile bool lostCount;

        public SandboxWatch(string root, string[] patterns, string[] skipFolders, string groupSid, string accountSid)
        {
            this.root = Path.GetFullPath(root).TrimEnd('\\');
            rootLength = this.root.Length + 1;
            group = new SecurityIdentifier(groupSid);
            account = new SecurityIdentifier(accountSid);
            skip = new HashSet<string>(skipFolders ?? new string[0], StringComparer.OrdinalIgnoreCase);
            // where the project folder really is (a link or a short name above it is fine)
            using (SafeFileHandle h = CreateFileW(Long(this.root), READ_CONTROL | FILE_READ_ATTRIBUTES | SYNCHRONIZE, SHARE_ALL, IntPtr.Zero, OPEN_EXISTING, FLAG_BACKUP_SEMANTICS, IntPtr.Zero))
            {
                if (h.IsInvalid) throw new IOException("the project folder cannot be opened (Windows error " + Marshal.GetLastWin32Error() + ")");
                rootFinal = FinalPath(h);
                if (rootFinal == null) throw new IOException("the place of the project folder cannot be read");
            }
            var fileParts = new List<string>();
            var folderParts = new List<string>();
            var topParts = new List<string>();
            var wildParts = new List<string>();
            foreach (string raw in patterns ?? new string[0])
            {
                string p = (raw ?? "").Trim().Replace('\\', '/').ToLowerInvariant();
                // .git is watched as a whole (below); empty patterns mean nothing
                if (p.Length == 0 || p == ".git" || p == ".git/*") continue;
                // (what lies inside a protected folder is not looked at one by one: the folder is)
                string whole = p.EndsWith("/*") ? p.Substring(0, p.Length - 2) : p;
                string last = whole.Substring(whole.LastIndexOf('/') + 1);
                if (last.IndexOf('*') >= 0 || last.IndexOf('?') >= 0) wildParts.Add(ToRegex(last));
                else names.Add(last);
                if (p.EndsWith("/*")) folderParts.Add(ToRegex(whole));
                else if (p.IndexOf('/') < 0 && p.IndexOf('*') < 0 && p.IndexOf('?') < 0 &&
                         Regex.IsMatch(p, @"\.(exe|cmd|bat|com)$"))
                {
                    // a program named like one of the system counts next to the project folder, where
                    // a terminal opened there finds it first (python.exe of a venv deeper down is normal)
                    topParts.Add(ToRegex(p));
                }
                else fileParts.Add(ToRegex(p));
            }
            var opts = RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;
            nameWildcards = new Regex(wildParts.Count > 0 ? "^(" + string.Join("|", wildParts) + ")$" : "(?!)", opts);
            var all = new List<string>();
            if (fileParts.Count > 0) all.Add("(^|/)(" + string.Join("|", fileParts) + ")$");
            if (topParts.Count > 0) all.Add("^(" + string.Join("|", topParts) + ")$");
            files = new Regex(all.Count > 0 ? string.Join("|", all) : "(?!)", opts);
            folders = new Regex(folderParts.Count > 0 ? "(^|/)(" + string.Join("|", folderParts) + ")$" : "(?!)", opts);
        }

        static string ToRegex(string pattern)
        {
            var sb = new StringBuilder();
            foreach (char c in pattern)
            {
                if (c == '*') sb.Append("[^/]*");
                else if (c == '?') sb.Append("[^/]");
                else sb.Append(Regex.Escape(c.ToString()));
            }
            return sb.ToString();
        }

        // A path in the form that has no length limit (\\?\C:\... or \\?\UNC\server\share\...).
        static string Long(string full)
        {
            if (full.StartsWith(@"\\?\")) return full;
            if (full.StartsWith(@"\\")) return @"\\?\UNC\" + full.Substring(2);
            return @"\\?\" + full;
        }

        static string FinalPath(SafeFileHandle h)
        {
            var sb = new StringBuilder(1024);
            uint n = GetFinalPathNameByHandleW(h, sb, (uint)sb.Capacity, 0);
            if (n > sb.Capacity)
            {
                sb = new StringBuilder((int)n + 1);
                n = GetFinalPathNameByHandleW(h, sb, (uint)sb.Capacity, 0);
            }
            return n == 0 ? null : sb.ToString().TrimEnd('\\');
        }

        // ---------- the walk ----------

        enum Kind { None, Git, File, Folder }

        string Relative(string full)
        {
            return full.Length <= rootLength ? "" : full.Substring(rootLength).Replace('\\', '/');
        }

        // Could a file or folder of this name be protected somewhere? (a quick look, most names are not)
        bool Candidate(string name)
        {
            return name.Equals(".git", StringComparison.OrdinalIgnoreCase) || names.Contains(name) || nameWildcards.IsMatch(name);
        }

        Kind KindOf(string rel, bool isFolder)
        {
            int slash = rel.LastIndexOf('/');
            string name = slash < 0 ? rel : rel.Substring(slash + 1);
            if (name.Equals(".git", StringComparison.OrdinalIgnoreCase)) return Kind.Git;
            if (!Candidate(name)) return Kind.None;
            if (isFolder && folders.IsMatch(rel)) return Kind.Folder;
            if (files.IsMatch(rel)) return Kind.File;
            return Kind.None;
        }

        // Every .git and every protected file or folder below $start. Not looked into: git folders,
        // protected folders (their deny entry passes on to all inside), links, and the folders of
        // caches (only a .git right in them counts).
        void Walk(string start, Action<string, Kind> visit)
        {
            var stack = new Stack<DirectoryInfo>();
            stack.Push(new DirectoryInfo(start));
            while (stack.Count > 0)
            {
                DirectoryInfo dir = stack.Pop();
                IEnumerable<FileSystemInfo> entries;
                try { entries = dir.EnumerateFileSystemInfos(); } catch { continue; }
                try
                {
                    foreach (FileSystemInfo e in entries)
                    {
                        bool isFolder = (e.Attributes & FileAttributes.Directory) != 0;
                        bool isLink = (e.Attributes & FileAttributes.ReparsePoint) != 0;
                        Kind kind = Candidate(e.Name) ? KindOf(Relative(e.FullName), isFolder) : Kind.None;
                        if (kind != Kind.None) { visit(e.FullName, kind); continue; }
                        if (!isFolder || isLink) continue;
                        if (skip.Contains(e.Name))
                        {
                            string inner = Path.Combine(e.FullName, ".git");
                            if (Directory.Exists(inner) || File.Exists(inner)) visit(inner, Kind.Git);
                            continue;
                        }
                        stack.Push((DirectoryInfo)e);
                    }
                }
                catch { }
            }
        }

        // ---------- one object, through one handle ----------

        sealed class Item : IDisposable
        {
            public SafeFileHandle Handle;
            public bool CanChange;          // opened with the right to delete and rename
            public bool CanProtect;         // opened with the right to change its rights
            public bool Elsewhere;          // the path leads somewhere else (a link on the way)
            public bool IsFolder, IsLink, Denied;
            public SecurityIdentifier Owner;
            public byte[] Descriptor;       // owner and rights as read through the handle
            public string Id;
            public void Dispose() { if (Handle != null) Handle.Dispose(); }
        }

        // Opens what is at $full itself (a link, not what it points to) and reads what the watch needs.
        // null when nothing is there any more.
        Item Open(string full)
        {
            uint flags = FLAG_BACKUP_SEMANTICS | FLAG_OPEN_REPARSE_POINT;
            uint look = READ_CONTROL | FILE_READ_ATTRIBUTES | SYNCHRONIZE;
            // as much as Windows gives: a process of the command may keep it open without letting others
            // delete it (judge it now, act after the command)
            uint[] tries = { look | DELETE | WRITE_DAC, look | DELETE, look | WRITE_DAC, look };
            var item = new Item();
            foreach (uint access in tries)
            {
                item.Handle = CreateFileW(Long(full), access, SHARE_ALL, IntPtr.Zero, OPEN_EXISTING, flags, IntPtr.Zero);
                if (!item.Handle.IsInvalid)
                {
                    item.CanChange = (access & DELETE) != 0;
                    item.CanProtect = (access & WRITE_DAC) != 0;
                    break;
                }
                int error = Marshal.GetLastWin32Error();
                item.Handle.Dispose();
                // 2, 3: nothing there (any more)
                if (error == 2 || error == 3) return null;
            }
            if (item.Handle.IsInvalid) { item.Dispose(); return null; }
            BY_HANDLE_FILE_INFORMATION info;
            if (!GetFileInformationByHandle(item.Handle, out info)) { item.Dispose(); return null; }
            item.IsFolder = (info.FileAttributes & (uint)FileAttributes.Directory) != 0;
            item.IsLink = (info.FileAttributes & (uint)FileAttributes.ReparsePoint) != 0;
            item.Id = info.VolumeSerialNumber.ToString("x") + ":" + info.FileIndexHigh.ToString("x") + ":" + info.FileIndexLow.ToString("x");
            string final = FinalPath(item.Handle);
            string rel = Relative(full);
            string expected = rel.Length == 0 ? rootFinal : rootFinal + "\\" + rel.Replace('/', '\\');
            item.Elsewhere = final == null || !final.Equals(expected, StringComparison.OrdinalIgnoreCase);
            IntPtr o, g, d, s, sd;
            if (GetSecurityInfo(item.Handle, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION, out o, out g, out d, out s, out sd) == 0)
            {
                try
                {
                    var bytes = new byte[GetSecurityDescriptorLength(sd)];
                    Marshal.Copy(sd, bytes, 0, bytes.Length);
                    var raw = new RawSecurityDescriptor(bytes, 0);
                    item.Descriptor = bytes;
                    item.Owner = raw.Owner;
                    item.Denied = DeniesGroup(raw.DiscretionaryAcl);
                }
                catch { }
                finally { LocalFree(sd); }
            }
            return item;
        }

        // Does an entry (its own or passed on) keep the group of the sandbox from changing it?
        bool DeniesGroup(RawAcl acl)
        {
            if (acl == null) return false;
            foreach (GenericAce ace in acl)
            {
                var c = ace as CommonAce;
                if (c == null || c.AceQualifier != AceQualifier.AccessDenied || !group.Equals(c.SecurityIdentifier)) continue;
                if ((c.AceFlags & AceFlags.InheritOnly) != 0) continue;
                if ((c.AccessMask & (int)DenyFile) == (int)DenyFile) return true;
            }
            return false;
        }

        static bool DeleteThrough(Item item)
        {
            return item.CanChange && SetFileInformationByHandle(item.Handle, FileDispositionInfo, new byte[] { 1 }, 1);
        }

        // The deny entry for a file or a link itself, written through the handle (nothing inside to pass
        // it on to; a link then can neither be pointed elsewhere nor deleted by the group).
        bool DenyThrough(Item item)
        {
            if (item.Denied) return true;
            if (!item.CanProtect || item.Descriptor == null || (item.IsFolder && !item.IsLink)) return false;
            try
            {
                var sd = new RawSecurityDescriptor(item.Descriptor, 0);
                if (sd.DiscretionaryAcl == null) return false;
                sd.DiscretionaryAcl.InsertAce(0, new CommonAce(AceFlags.None, AceQualifier.AccessDenied, (int)DenyFile, group, false, null));
                // keep the mark "passed on automatically", which Windows drops unless asked
                if ((sd.ControlFlags & ControlFlags.DiscretionaryAclAutoInherited) != 0)
                    sd.SetFlags(sd.ControlFlags | ControlFlags.DiscretionaryAclAutoInheritRequired);
                var bytes = new byte[sd.BinaryLength];
                sd.GetBinaryForm(bytes, 0);
                return SetKernelObjectSecurity(item.Handle, DACL_SECURITY_INFORMATION, bytes);
            }
            catch { return false; }
        }

        // Where a link points, when that is inside the project folder (else null).
        string TargetInside(string full)
        {
            using (SafeFileHandle h = CreateFileW(Long(full), READ_CONTROL | FILE_READ_ATTRIBUTES | SYNCHRONIZE, SHARE_ALL, IntPtr.Zero, OPEN_EXISTING, FLAG_BACKUP_SEMANTICS, IntPtr.Zero))
            {
                if (h.IsInvalid) return null;
                string final = FinalPath(h);
                if (final == null || !final.StartsWith(rootFinal + "\\", StringComparison.OrdinalIgnoreCase)) return null;
                return root + final.Substring(rootFinal.Length);
            }
        }

        // Renames the object to <name>.blocked-by-sandbox (-2, -3 ...) in the folder it is in now.
        // Returns the new name or null.
        static string RenameThrough(Item item, string full)
        {
            if (!item.CanChange) return null;
            string leaf = Path.GetFileName(full);
            for (int n = 1; n < 50; n++)
            {
                string name = leaf + ".blocked-by-sandbox" + (n == 1 ? "" : "-" + n);
                byte[] text = Encoding.Unicode.GetBytes(name);
                // FILE_RENAME_INFORMATION: ReplaceIfExists (no), RootDirectory (none: a bare name stays
                // in the same folder), FileNameLength, FileName
                int nameAt = IntPtr.Size == 8 ? 20 : 12, lengthAt = IntPtr.Size == 8 ? 16 : 8;
                var buffer = new byte[nameAt + text.Length + 2];
                BitConverter.GetBytes(text.Length).CopyTo(buffer, lengthAt);
                text.CopyTo(buffer, nameAt);
                IO_STATUS_BLOCK io;
                int status = NtSetInformationFile(item.Handle, out io, buffer, buffer.Length, FileRenameInformation);
                if (status == 0) return name;
                // 0xC0000035 STATUS_OBJECT_NAME_COLLISION: try the next number
                if (status != unchecked((int)0xC0000035)) return null;
            }
            return null;
        }

        // ---------- rights ----------

        static bool HasDeny(FileSystemSecurity sec, SecurityIdentifier who, FileSystemRights rights, InheritanceFlags inherit)
        {
            foreach (FileSystemAccessRule r in sec.GetAccessRules(true, false, typeof(SecurityIdentifier)))
            {
                if (r.AccessControlType != AccessControlType.Deny || !who.Equals(r.IdentityReference)) continue;
                if ((r.FileSystemRights & rights) == rights && (r.InheritanceFlags & inherit) == inherit &&
                    (r.PropagationFlags & PropagationFlags.InheritOnly) == 0) return true;
            }
            return false;
        }

        // The group of the sandbox may not change this file or folder (a folder: nor anything in it).
        // By name, so Windows passes the entry on to what is inside: only before the command, when no
        // process of the sandbox runs. Returns "" or what went wrong.
        string Deny(string path, bool isFolder)
        {
            try
            {
                if (isFolder)
                {
                    var inherit = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
                    DirectorySecurity ds = Directory.GetAccessControl(path, AccessControlSections.Access);
                    bool there = HasDeny(ds, group, DenyFolder, inherit);
                    if (there && ReachesInside(path)) return "";
                    // Windows does not pass the entry on, without an error, while a program holds the
                    // folder open with the right to delete it, and later only passes on a change: an
                    // entry that did not arrive is taken away and set again, then checked
                    for (int attempt = 0; attempt < 2; attempt++)
                    {
                        if (there)
                        {
                            ds.RemoveAccessRuleAll(new FileSystemAccessRule(group, FileSystemRights.Read, AccessControlType.Deny));
                            Directory.SetAccessControl(path, ds);
                            ds = Directory.GetAccessControl(path, AccessControlSections.Access);
                        }
                        ds.AddAccessRule(new FileSystemAccessRule(group, DenyFolder, inherit, PropagationFlags.None, AccessControlType.Deny));
                        Directory.SetAccessControl(path, ds);
                        there = true;
                        if (ReachesInside(path)) return "";
                        System.Threading.Thread.Sleep(200);
                        ds = Directory.GetAccessControl(path, AccessControlSections.Access);
                    }
                    return "the deny entry does not reach what is inside (a program keeps the folder open?)";
                }
                else
                {
                    FileSecurity fs = File.GetAccessControl(path, AccessControlSections.Access);
                    if (HasDeny(fs, group, DenyFile, InheritanceFlags.None)) return "";
                    fs.AddAccessRule(new FileSystemAccessRule(group, DenyFile, AccessControlType.Deny));
                    File.SetAccessControl(path, fs);
                }
                return "";
            }
            catch (Exception e) { return e.Message; }
        }

        // Did the deny entry of a folder reach the first things in it (those that take entries from
        // their folder)?
        bool ReachesInside(string folder)
        {
            int n = 0;
            try
            {
                foreach (string e in Directory.EnumerateFileSystemEntries(folder))
                {
                    if (++n > 8) break;
                    FileSystemSecurity sec = (File.GetAttributes(e) & FileAttributes.Directory) != 0
                        ? (FileSystemSecurity)Directory.GetAccessControl(e, AccessControlSections.Access)
                        : File.GetAccessControl(e, AccessControlSections.Access);
                    if (sec.AreAccessRulesProtected) continue;
                    bool denied = false;
                    foreach (FileSystemAccessRule r in sec.GetAccessRules(true, true, typeof(SecurityIdentifier)))
                        if (r.AccessControlType == AccessControlType.Deny && group.Equals(r.IdentityReference) &&
                            (r.FileSystemRights & DenyFile) == DenyFile) { denied = true; break; }
                    if (!denied) return false;
                }
            }
            catch { return false; }
            return true;
        }

        // The folders between the project folder and a protected path may not be renamed or deleted by
        // the group, so nothing can take the place of what is protected there. An entry for the folder
        // itself, passed on to nothing, written without walking through what is inside.
        string KeepInPlace(string full)
        {
            string dir = Path.GetDirectoryName(full);
            while (dir != null && dir.Length >= rootLength)
            {
                try
                {
                    var sd = new RawSecurityDescriptor(Directory.GetAccessControl(dir, AccessControlSections.Access).GetSecurityDescriptorBinaryForm(), 0);
                    RawAcl acl = sd.DiscretionaryAcl;
                    bool there = false;
                    if (acl != null)
                        foreach (GenericAce ace in acl)
                        {
                            var c = ace as CommonAce;
                            if (c != null && c.AceQualifier == AceQualifier.AccessDenied && !c.IsInherited && group.Equals(c.SecurityIdentifier) &&
                                (c.AccessMask & (int)DELETE) != 0) { there = true; break; }
                        }
                    if (!there && acl != null)
                    {
                        // first, where Windows expects the entries that deny
                        acl.InsertAce(0, new CommonAce(AceFlags.None, AceQualifier.AccessDenied, (int)DELETE, group, false, null));
                        // keep the mark "passed on automatically", which SetFileSecurity drops unless asked
                        if ((sd.ControlFlags & ControlFlags.DiscretionaryAclAutoInherited) != 0)
                            sd.SetFlags(sd.ControlFlags | ControlFlags.DiscretionaryAclAutoInheritRequired);
                        var bytes = new byte[sd.BinaryLength];
                        sd.GetBinaryForm(bytes, 0);
                        if (!SetFileSecurityW(Long(dir), DACL_SECURITY_INFORMATION, bytes))
                            return Relative(dir) + " (Windows error " + Marshal.GetLastWin32Error() + ")";
                    }
                }
                catch (Exception e) { return Relative(dir) + " (" + e.Message + ")"; }
                dir = Path.GetDirectoryName(dir);
            }
            return "";
        }

        // A .git file names the real git folder ("gitdir: <path>"); inside the project it is protected
        // like a .git folder.
        string GitDirOfFile(string gitFile)
        {
            try
            {
                string text = File.ReadAllText(gitFile).Trim();
                if (!text.StartsWith("gitdir:", StringComparison.OrdinalIgnoreCase)) return null;
                string target = text.Substring(7).Trim().Replace('/', '\\');
                if (!Path.IsPathRooted(target)) target = Path.Combine(Path.GetDirectoryName(gitFile), target);
                target = Path.GetFullPath(target).TrimEnd('\\');
                if (!target.StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase) || !Directory.Exists(target)) return null;
                return target;
            }
            catch { return null; }
        }

        void Note(string text)
        {
            if (notes.Count < MaxNotes) notes.Add(text); else moreNotes++;
        }

        // What the account made under a protected name goes: a file or an empty folder is deleted, a
        // folder with something in it is renamed. Through the handle only. false when it is still held
        // open by the command.
        bool RemoveMade(Item item, string full)
        {
            string rel = Relative(full);
            if (DeleteThrough(item)) { Note("removed " + rel + (item.IsFolder ? "/" : "") + " (made by the command)"); return true; }
            string name = RenameThrough(item, full);
            if (name != null) { Note("renamed " + rel + " to " + name + " (made by the command)"); return true; }
            return false;
        }

        // ---------- before the command ----------

        // Makes the repositories and protected paths read-only for the group and remembers them.
        // Returns "" or the paths that could not be protected.
        public string Prepare()
        {
            var watch = System.Diagnostics.Stopwatch.StartNew();
            var failed = new List<string>();
            lock (gate)
            {
                before.Clear();
                fixedPlaces.Clear();
                Walk(root, (full, kind) =>
                {
                    string rel = Relative(full);
                    string id, problem = "";
                    bool isFolder, isLink = false;
                    using (Item item = Open(full))
                    {
                        if (item == null) return;
                        // no process of the sandbox runs now: a path that leads elsewhere is not normal
                        if (item.Elsewhere) { failed.Add(rel + " (it is reached through a link)"); return; }
                        bool made = item.Owner != null && item.Owner.Equals(account);
                        // what the account made is no danger in .git (git refuses it for the user) and
                        // goes elsewhere, a link of it too
                        if (made && kind == Kind.Git && !item.IsLink) return;
                        if (made && item.IsLink) { if (DeleteThrough(item)) Note("removed the link " + rel); return; }
                        if (made) { if (!RemoveMade(item, full)) Note("could not remove " + rel); return; }
                        // a link of the user under a protected name (settings shared between folders): the
                        // link itself is protected through its handle, what it points to below
                        if (item.IsLink && !DenyThrough(item)) problem = "its rights cannot be changed";
                        id = item.Id;
                        isFolder = item.IsFolder;
                        isLink = item.IsLink;
                    }
                    // by name, with the handle closed: Windows passes a new entry on to what is inside a
                    // folder only when nobody else holds it open with the right to delete it
                    if (problem.Length == 0 && isLink)
                    {
                        string target = TargetInside(full);
                        if (target != null) problem = Deny(target, Directory.Exists(target));
                    }
                    else if (problem.Length == 0)
                    {
                        problem = Deny(full, isFolder);
                        if (problem.Length == 0 && kind == Kind.Git && !isFolder)
                        {
                            string target = GitDirOfFile(full);
                            if (target != null) problem = Deny(target, true);
                        }
                    }
                    if (problem.Length == 0) problem = KeepInPlace(full);
                    if (problem.Length > 0) { failed.Add(rel + " (" + problem + ")"); return; }
                    // writing the rights does not change the id of the object
                    before[full] = id;
                    fixedPlaces.Add(full);
                });
            }
            violation = false;
            PrepareMilliseconds = watch.Elapsed.TotalMilliseconds;
            return string.Join("; ", failed);
        }

        // ---------- during the command ----------

        public void Start()
        {
            watcher = new FileSystemWatcher(root);
            watcher.IncludeSubdirectories = true;
            watcher.InternalBufferSize = 65536;
            watcher.NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName;
            watcher.Created += (s, e) => Seen(e.FullPath);
            watcher.Renamed += (s, e) => Seen(e.FullPath);
            // too many changes at once: look at everything
            watcher.Error += (s, e) => { lostCount = true; lock (gate) { Scan(); } };
            watcher.EnableRaisingEvents = true;
        }

        void Seen(string full)
        {
            try
            {
                string rel = Relative(full);
                if (rel.Length == 0) return;
                string[] parts = rel.Split('/');
                // inside a git folder: git folders of the user are read-only for the sandbox, those of
                // the sandbox are refused by git (and must stay the account's)
                for (int i = 0; i < parts.Length - 1; i++)
                    if (parts[i].Equals(".git", StringComparison.OrdinalIgnoreCase)) return;
                FileAttributes attributes;
                try { attributes = File.GetAttributes(full); } catch { return; }
                bool isFolder = (attributes & FileAttributes.Directory) != 0;
                // every folder that appears, caches too (a package there runs later as well)
                if (isFolder && (attributes & FileAttributes.ReparsePoint) == 0) lock (gate) madeFolders.Add(full);
                // inside a cache folder only a .git counts for the rest
                for (int i = 0; i < parts.Length - 1; i++)
                    if (skip.Contains(parts[i]) && !parts[parts.Length - 1].Equals(".git", StringComparison.OrdinalIgnoreCase)) return;
                Kind kind = KindOf(rel, isFolder);
                lock (gate)
                {
                    if (kind != Kind.None) Judge(full, kind);
                    // a folder made or moved here may bring a .git or a protected name along
                    else if (isFolder && (attributes & FileAttributes.ReparsePoint) == 0 && !skip.Contains(parts[parts.Length - 1]))
                        Walk(full, (f, k) => Judge(f, k));
                }
            }
            catch { }
        }

        // A .git or protected path: was it there before, made by the command, protected, or something
        // of the user moved there? What a process of the command still holds open is tried again for
        // about a second; after that the command ends and Finish deals with it.
        void Judge(string full, Kind kind)
        {
            for (int attempt = 1; !JudgeOnce(full, kind, attempt == 10); attempt++)
                System.Threading.Thread.Sleep(100);
        }

        // false: it needs to be dealt with but is held open; try again
        bool JudgeOnce(string full, Kind kind, bool last)
        {
            using (Item item = Open(full))
            {
                if (item == null) return true;
                string rel = Relative(full);
                string id;
                if (before.TryGetValue(full, out id) && id == item.Id) return true;
                if (item.Elsewhere)
                {
                    // a folder on the way was swapped for a link while the watch looked: nothing is done
                    // through it, the command ends and Finish looks again
                    Note("stopped: " + rel + " was reached through a link");
                    violation = true;
                    return true;
                }
                bool made = item.Owner != null && item.Owner.Equals(account);
                if (!item.CanChange && !last && ((made && kind != Kind.Git) || item.IsLink || (!made && !item.Denied))) return false;
                if (item.IsLink)
                {
                    // a link under a protected name leads git or an editor somewhere else: one of the
                    // account goes, one of the user (moved here) is renamed
                    if (made && DeleteThrough(item)) Note("removed the link " + rel);
                    else
                    {
                        string renamed = RenameThrough(item, full);
                        Note(renamed != null ? "renamed the link " + rel + " to " + renamed : "could not remove the link " + rel + " yet");
                    }
                    violation = true;
                    return true;
                }
                if (made)
                {
                    // made by the sandbox: a repository of its own is harmless (git refuses it for the
                    // user); anything else goes
                    if (kind != Kind.Git && !RemoveMade(item, full))
                    {
                        Note("could not remove " + rel + " yet");
                        violation = true;
                    }
                    return true;
                }
                if (item.Denied)
                {
                    // protected before and moved along with a folder above it: still the user's
                    before[full] = item.Id;
                    return true;
                }
                if (fixedPlaces.Contains(full) && !item.IsFolder && DenyThrough(item))
                {
                    // where a protected file of the user was, which the sandbox can neither move nor
                    // free (KeepInPlace): an editor of the user replaced it, so it is protected again
                    before[full] = item.Id;
                    return true;
                }
                // owned by the user (or unknown) and changeable by the sandbox until now: moved here, and
                // git and editors would trust it
                string name = RenameThrough(item, full);
                if (name != null) Note("renamed " + rel + " to " + name + " (something of yours was moved there)");
                else Note("could not rename " + rel + " yet");
                violation = true;
                return true;
            }
        }

        void Scan()
        {
            var found = new List<KeyValuePair<string, Kind>>();
            Walk(root, (full, kind) => found.Add(new KeyValuePair<string, Kind>(full, kind)));
            foreach (var f in found) Judge(f.Key, f.Value);
        }

        // ---------- after the command ----------

        // Stops the watcher, checks the whole folder once more, gives the folders the command made to the
        // user, and returns what was done.
        public string[] Finish()
        {
            if (watcher != null)
            {
                watcher.EnableRaisingEvents = false;
                watcher.Dispose();
                watcher = null;
            }
            lock (gate)
            {
                Scan();
                var done = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                if (lostCount) TakeFolders(root, rootFinal, rootLength, account, done);
                else
                {
                    // parents first, so a folder moved in with all inside is walked once
                    var list = new List<string>(madeFolders);
                    list.Sort((a, b) => a.Length.CompareTo(b.Length));
                    foreach (string folder in list) TakeFolders(folder, rootFinal, rootLength, account, done);
                }
                madeFolders.Clear();
                lostCount = false;
                var result = new List<string>(notes);
                if (moreNotes > 0) result.Add("and " + moreNotes + " more");
                notes.Clear();
                moreNotes = 0;
                return result.ToArray();
            }
        }

        public void Dispose()
        {
            if (watcher != null) { watcher.Dispose(); watcher = null; }
        }

        // ---------- folders of the account ----------

        // The folders the account owns in a project give it the rights of an owner (changing their
        // rights) from any command, also one of another project: the user takes them over. Every
        // folder below and including start, not through links, not a git folder or what is in it
        // (git trusts what the user owns; a repository the sandbox made must stay the account's).
        // Through a handle whose place is checked. done: folders handled already.
        static void TakeFolders(string start, string rootFinal, int rootLength, SecurityIdentifier account, HashSet<string> done)
        {
            byte[] owner = OwnerDescriptor(WindowsIdentity.GetCurrent().User);
            var stack = new Stack<string>();
            stack.Push(start);
            while (stack.Count > 0)
            {
                string dir = stack.Pop();
                if (!done.Add(dir)) continue;
                if (Path.GetFileName(dir).Equals(".git", StringComparison.OrdinalIgnoreCase)) continue;
                GiveToUser(dir, rootFinal, rootLength, account, owner);
                try
                {
                    foreach (string sub in Directory.EnumerateDirectories(dir))
                        if ((File.GetAttributes(sub) & FileAttributes.ReparsePoint) == 0) stack.Push(sub);
                }
                catch { }
            }
        }

        static byte[] OwnerDescriptor(SecurityIdentifier user)
        {
            var sd = new RawSecurityDescriptor(ControlFlags.None, user, null, null, null);
            var bytes = new byte[sd.BinaryLength];
            sd.GetBinaryForm(bytes, 0);
            return bytes;
        }

        static void GiveToUser(string dir, string rootFinal, int rootLength, SecurityIdentifier account, byte[] owner)
        {
            const uint WRITE_OWNER = 0x80000;
            using (SafeFileHandle h = CreateFileW(Long(dir), READ_CONTROL | WRITE_OWNER | FILE_READ_ATTRIBUTES | SYNCHRONIZE, SHARE_ALL,
                       IntPtr.Zero, OPEN_EXISTING, FLAG_BACKUP_SEMANTICS | FLAG_OPEN_REPARSE_POINT, IntPtr.Zero))
            {
                if (h.IsInvalid) return;
                string final = FinalPath(h);
                string expected = dir.Length < rootLength ? rootFinal : rootFinal + "\\" + dir.Substring(rootLength);
                if (final == null || !final.Equals(expected, StringComparison.OrdinalIgnoreCase)) return;
                IntPtr o, g, d, s, sd;
                if (GetSecurityInfo(h, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION, out o, out g, out d, out s, out sd) != 0) return;
                bool ours;
                try { ours = account.Equals(new SecurityIdentifier(o)); }
                finally { LocalFree(sd); }
                if (ours) SetKernelObjectSecurity(h, OWNER_SECURITY_INFORMATION, owner);
            }
        }

        // Once for a project folder used with the sandbox before (lib\Sandbox.ps1): the folders the
        // account made there go to the user.
        public static void TakeFoldersOf(string root, string accountSid)
        {
            string full = Path.GetFullPath(root).TrimEnd('\\');
            string final;
            using (SafeFileHandle h = CreateFileW(Long(full), READ_CONTROL | FILE_READ_ATTRIBUTES | SYNCHRONIZE, SHARE_ALL, IntPtr.Zero, OPEN_EXISTING, FLAG_BACKUP_SEMANTICS, IntPtr.Zero))
            {
                if (h.IsInvalid) return;
                final = FinalPath(h);
            }
            if (final == null) return;
            TakeFolders(full, final, full.Length + 1, new SecurityIdentifier(accountSid), new HashSet<string>(StringComparer.OrdinalIgnoreCase));
        }
    }
}
