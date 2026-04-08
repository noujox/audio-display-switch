Set-StrictMode -Version Latest

function Initialize-AudioInterop {
    if (-not ("AudioInterop.CoreAudioHelper" -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace AudioInterop {
    public enum EDataFlow {
        eRender,
        eCapture,
        eAll,
        EDataFlow_enum_count
    }

    public enum ERole {
        eConsole,
        eMultimedia,
        eCommunications,
        ERole_enum_count
    }

    [Flags]
    public enum DEVICE_STATE : uint {
        ACTIVE = 0x00000001,
        DISABLED = 0x00000002,
        NOTPRESENT = 0x00000004,
        UNPLUGGED = 0x00000008,
        ALL = 0x0000000F
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROPERTYKEY {
        public Guid fmtid;
        public uint pid;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct PROPVARIANT {
        [FieldOffset(0)]
        public ushort vt;
        [FieldOffset(2)]
        public ushort wReserved1;
        [FieldOffset(4)]
        public ushort wReserved2;
        [FieldOffset(6)]
        public ushort wReserved3;
        [FieldOffset(8)]
        public IntPtr pointerValue;
        [FieldOffset(8)]
        public byte byteValue;
        [FieldOffset(8)]
        public long longValue;
    }

    [ComImport]
    [Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        int GetCount(out uint cProps);
        int GetAt(uint iProp, out PROPERTYKEY pkey);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        int SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        int Commit();
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
        int OpenPropertyStore(int stgmAccess, out IPropertyStore ppProperties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
        int GetState(out DEVICE_STATE pdwState);
    }

    [ComImport]
    [Guid("0BD7A1BE-7A1A-44DB-8397-C0A6A4EAA4B5")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection {
        int GetCount(out uint pcDevices);
        int Item(uint nDevice, out IMMDevice ppDevice);
    }

    [ComImport]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(EDataFlow dataFlow, DEVICE_STATE dwStateMask, out IMMDeviceCollection ppDevices);
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice ppEndpoint);
        int GetDevice(string pwstrId, out IMMDevice ppDevice);
        int RegisterEndpointNotificationCallback(IntPtr pClient);
        int UnregisterEndpointNotificationCallback(IntPtr pClient);
    }

    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorComObject {
    }

    public class AudioEndpoint {
        public string Id { get; set; }
        public string Name { get; set; }
        public bool IsDefault { get; set; }
        public string State { get; set; }
    }

    public static class CoreAudioHelper {
        private static readonly PROPERTYKEY PKEY_Device_FriendlyName = new PROPERTYKEY {
            fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"),
            pid = 14
        };

        [DllImport("ole32.dll")]
        private static extern int PropVariantClear(ref PROPVARIANT pvar);

        private static IMMDeviceEnumerator CreateEnumerator() {
            return (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
        }

        private static string ReadPropVariantString(ref PROPVARIANT pv) {
            const ushort VT_LPWSTR = 31;
            const ushort VT_BSTR = 8;
            const ushort VT_LPSTR = 30;

            if (pv.vt == VT_LPWSTR || pv.vt == VT_BSTR) {
                return Marshal.PtrToStringUni(pv.pointerValue);
            }

            if (pv.vt == VT_LPSTR) {
                return Marshal.PtrToStringAnsi(pv.pointerValue);
            }

            return string.Empty;
        }

        private static string GetFriendlyName(IMMDevice device) {
            IPropertyStore store = null;
            PROPVARIANT pv = new PROPVARIANT();

            try {
                int hr = device.OpenPropertyStore(0, out store);
                if (hr != 0 || store == null) {
                    return string.Empty;
                }

                PROPERTYKEY key = PKEY_Device_FriendlyName;
                hr = store.GetValue(ref key, out pv);
                if (hr != 0) {
                    return string.Empty;
                }

                return ReadPropVariantString(ref pv);
            }
            finally {
                PropVariantClear(ref pv);
                if (store != null) {
                    Marshal.ReleaseComObject(store);
                }
            }
        }

        public static AudioEndpoint GetDefaultRenderEndpoint() {
            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;

            try {
                enumerator = CreateEnumerator();
                int hr = enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out device);
                if (hr != 0 || device == null) {
                    return null;
                }

                string id;
                DEVICE_STATE state;
                device.GetId(out id);
                device.GetState(out state);

                return new AudioEndpoint {
                    Id = id,
                    Name = GetFriendlyName(device),
                    IsDefault = true,
                    State = state.ToString()
                };
            }
            finally {
                if (device != null) {
                    Marshal.ReleaseComObject(device);
                }
                if (enumerator != null) {
                    Marshal.ReleaseComObject(enumerator);
                }
            }
        }

        public static AudioEndpoint[] GetRenderEndpoints() {
            IMMDeviceEnumerator enumerator = null;
            IMMDeviceCollection collection = null;
            string defaultId = string.Empty;
            var list = new List<AudioEndpoint>();

            try {
                AudioEndpoint defaultEndpoint = GetDefaultRenderEndpoint();
                if (defaultEndpoint != null) {
                    defaultId = defaultEndpoint.Id;
                }

                enumerator = CreateEnumerator();
                int hr = enumerator.EnumAudioEndpoints(EDataFlow.eRender, DEVICE_STATE.ALL, out collection);
                if (hr != 0 || collection == null) {
                    return list.ToArray();
                }

                uint count;
                collection.GetCount(out count);

                for (uint i = 0; i < count; i++) {
                    IMMDevice device = null;
                    try {
                        collection.Item(i, out device);
                        if (device == null) {
                            continue;
                        }

                        string id;
                        DEVICE_STATE state;
                        device.GetId(out id);
                        device.GetState(out state);

                        list.Add(new AudioEndpoint {
                            Id = id,
                            Name = GetFriendlyName(device),
                            IsDefault = string.Equals(id, defaultId, StringComparison.Ordinal),
                            State = state.ToString()
                        });
                    }
                    finally {
                        if (device != null) {
                            Marshal.ReleaseComObject(device);
                        }
                    }
                }

                return list.ToArray();
            }
            finally {
                if (collection != null) {
                    Marshal.ReleaseComObject(collection);
                }
                if (enumerator != null) {
                    Marshal.ReleaseComObject(enumerator);
                }
            }
        }
    }
}
"@
    }
}

function Get-DefaultRenderAudioEndpoint {
    Initialize-AudioInterop
    $endpoint = [AudioInterop.CoreAudioHelper]::GetDefaultRenderEndpoint()

    if ($null -eq $endpoint) {
        return $null
    }

    [pscustomobject]@{
        Id        = [string]$endpoint.Id
        Name      = [string]$endpoint.Name
        IsDefault = [bool]$endpoint.IsDefault
        State     = [string]$endpoint.State
    }
}

function Get-RenderAudioEndpoints {
    $default = Get-DefaultRenderAudioEndpoint
    $defaultId = if ($null -eq $default) { "" } else { [string]$default.Id }

    $basePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
    if (-not (Test-Path -LiteralPath $basePath)) {
        return
    }

    $friendlyNameKey = "{a45c254e-df1c-4efd-8020-67d146a850e0},2"
    $descriptionKey = "{b3f8fa53-0004-438e-9003-51a46e139bfc},6"

    foreach ($endpointKey in (Get-ChildItem -LiteralPath $basePath)) {
        $guidPart = [string]$endpointKey.PSChildName
        $id = "{0.0.0.00000000}.$guidPart"

        $rootValues = Get-ItemProperty -LiteralPath $endpointKey.PSPath -ErrorAction SilentlyContinue
        $stateRaw = if ($null -eq $rootValues) { 0 } else { [int]$rootValues.DeviceState }
        $stateNibble = $stateRaw -band 0xF
        $state = switch ($stateNibble) {
            1 { "ACTIVE"; break }
            2 { "DISABLED"; break }
            4 { "NOTPRESENT"; break }
            8 { "UNPLUGGED"; break }
            default { "UNKNOWN" }
        }

        $propertiesPath = Join-Path $endpointKey.PSPath "Properties"
        $props = Get-ItemProperty -LiteralPath $propertiesPath -ErrorAction SilentlyContinue

        $name = ""
        if ($null -ne $props) {
            $friendly = $props.$friendlyNameKey
            $desc = $props.$descriptionKey

            if (-not [string]::IsNullOrWhiteSpace([string]$friendly) -and -not [string]::IsNullOrWhiteSpace([string]$desc)) {
                $name = "$friendly ($desc)"
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$friendly)) {
                $name = [string]$friendly
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$desc)) {
                $name = [string]$desc
            }
        }

        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = $guidPart
        }

        [pscustomobject]@{
            Id        = $id
            Name      = $name
            IsDefault = [string]::Equals($id, $defaultId, [System.StringComparison]::OrdinalIgnoreCase)
            State     = $state
        }
    }
}

function Initialize-AudioPolicyInterop {
    if (-not ("AudioPolicyInterop.PolicyConfigClient" -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace AudioPolicyInterop {
    public enum ERole {
        eConsole,
        eMultimedia,
        eCommunications,
        ERole_enum_count
    }

    [ComImport]
    [Guid("F8679F50-850A-41CF-9C72-430F290290C8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPolicyConfig {
        int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, IntPtr ppFormat);
        int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, int bDefault, IntPtr ppFormat);
        int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName);
        int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, IntPtr pEndpointFormat, IntPtr pMixFormat);
        int GetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, int bDefault, IntPtr pmftDefaultPeriod, IntPtr pmftMinimumPeriod);
        int SetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, IntPtr pmftPeriod);
        int GetShareMode([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, IntPtr pMode);
        int SetShareMode([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, IntPtr mode);
        int GetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, IntPtr key, IntPtr pv);
        int SetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, IntPtr key, IntPtr pv);
        int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, ERole role);
        int SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, int bVisible);
    }

    [ComImport]
    [Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")]
    class PolicyConfigClientComObject {
    }

    public static class PolicyConfigClient {
        public static void SetDefaultEndpoint(string endpointId) {
            if (string.IsNullOrWhiteSpace(endpointId)) {
                throw new ArgumentException("endpointId is empty");
            }

            IPolicyConfig policy = null;
            try {
                policy = (IPolicyConfig)new PolicyConfigClientComObject();

                int hr = policy.SetDefaultEndpoint(endpointId, ERole.eConsole);
                if (hr != 0) {
                    Marshal.ThrowExceptionForHR(hr);
                }

                hr = policy.SetDefaultEndpoint(endpointId, ERole.eMultimedia);
                if (hr != 0) {
                    Marshal.ThrowExceptionForHR(hr);
                }

                hr = policy.SetDefaultEndpoint(endpointId, ERole.eCommunications);
                if (hr != 0) {
                    Marshal.ThrowExceptionForHR(hr);
                }
            }
            finally {
                if (policy != null) {
                    Marshal.ReleaseComObject(policy);
                }
            }
        }
    }
}
"@
    }
}

function Set-DefaultRenderAudioEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EndpointId
    )

    Initialize-AudioPolicyInterop
    [AudioPolicyInterop.PolicyConfigClient]::SetDefaultEndpoint($EndpointId)
}
