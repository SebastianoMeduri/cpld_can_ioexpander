/*
 * PCANBasic.cs  --  Wrapper P/Invoke MINIMALE per l'API PCAN-Basic di PEAK.
 *
 * Copre solo cio' che serve alla GUI di test (Initialize/Uninitialize/Read/
 * Write/Reset/GetErrorText). Se preferisci, puoi sostituire questo file con il
 * PCANBasic.cs UFFICIALE fornito da PEAK (stesso namespace/classe): in tal caso
 * ELIMINA questo file per evitare definizioni duplicate.
 *
 * Richiede PCANBasic.dll (dal pacchetto/driver PCAN-Basic di PEAK) accanto
 * all'eseguibile o nel PATH; bitness del DLL = bitness dell'app (qui x64).
 */
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Peak.Can.Basic
{
    using TPCANHandle = System.UInt16;

    public enum TPCANStatus : uint
    {
        PCAN_ERROR_OK          = 0x00000,
        PCAN_ERROR_XMTFULL     = 0x00001,
        PCAN_ERROR_OVERRUN     = 0x00002,
        PCAN_ERROR_BUSLIGHT    = 0x00004,
        PCAN_ERROR_BUSHEAVY    = 0x00008,
        PCAN_ERROR_BUSOFF      = 0x00010,
        PCAN_ERROR_QRCVEMPTY   = 0x00020,
        PCAN_ERROR_QOVERRUN    = 0x00040,
        PCAN_ERROR_QXMTFULL    = 0x00080,
        PCAN_ERROR_ILLHW       = 0x01400,
        PCAN_ERROR_ILLNET      = 0x01800,
        PCAN_ERROR_ILLCLIENT   = 0x01C00,
        PCAN_ERROR_INITIALIZE  = 0x40000
    }

    [Flags]
    public enum TPCANMessageType : byte
    {
        PCAN_MESSAGE_STANDARD = 0x00,
        PCAN_MESSAGE_RTR      = 0x01,
        PCAN_MESSAGE_EXTENDED = 0x02
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct TPCANMsg
    {
        public uint ID;
        public byte MSGTYPE;
        public byte LEN;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public byte[] DATA;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct TPCANTimestamp
    {
        public uint   millis;
        public ushort millis_overflow;
        public ushort micros;
    }

    public static class PCANBasic
    {
        // Canali PCAN-USB
        public const TPCANHandle PCAN_USBBUS1 = 0x51;
        public const TPCANHandle PCAN_USBBUS2 = 0x52;
        public const TPCANHandle PCAN_USBBUS3 = 0x53;
        public const TPCANHandle PCAN_USBBUS4 = 0x54;
        public const TPCANHandle PCAN_USBBUS5 = 0x55;
        public const TPCANHandle PCAN_USBBUS6 = 0x56;
        public const TPCANHandle PCAN_USBBUS7 = 0x57;
        public const TPCANHandle PCAN_USBBUS8 = 0x58;

        // Bitrate (codici Btr0Btr1)
        public const ushort PCAN_BAUD_1M   = 0x0014;
        public const ushort PCAN_BAUD_500K = 0x001C;
        public const ushort PCAN_BAUD_250K = 0x011C;
        public const ushort PCAN_BAUD_125K = 0x031C;

        private const string DLL = "PCANBasic.dll";

        [DllImport(DLL, EntryPoint = "CAN_Initialize")]
        public static extern TPCANStatus Initialize(TPCANHandle Channel, ushort Btr0Btr1,
                                                     byte HwType, uint IOPort, ushort Interrupt);

        [DllImport(DLL, EntryPoint = "CAN_Uninitialize")]
        public static extern TPCANStatus Uninitialize(TPCANHandle Channel);

        [DllImport(DLL, EntryPoint = "CAN_Reset")]
        public static extern TPCANStatus Reset(TPCANHandle Channel);

        [DllImport(DLL, EntryPoint = "CAN_Read")]
        public static extern TPCANStatus Read(TPCANHandle Channel, out TPCANMsg Message,
                                              out TPCANTimestamp Timestamp);

        [DllImport(DLL, EntryPoint = "CAN_Write")]
        public static extern TPCANStatus Write(TPCANHandle Channel, ref TPCANMsg Message);

        [DllImport(DLL, EntryPoint = "CAN_GetErrorText")]
        public static extern TPCANStatus GetErrorText(TPCANStatus Error, ushort Language,
                                                      StringBuilder Buffer);

        public static string ErrorText(TPCANStatus st)
        {
            var sb = new StringBuilder(256);
            if (GetErrorText(st, 0, sb) == TPCANStatus.PCAN_ERROR_OK)
                return sb.ToString();
            return st.ToString();
        }
    }
}
