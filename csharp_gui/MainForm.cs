using System;
using System.Drawing;
using System.Globalization;
using System.Windows.Forms;
using Peak.Can.Basic;

namespace ExpanderTester
{
    public class MainForm : Form
    {
        // Codici FUNC del protocollo (vedi doc/protocol.md)
        private const int FUNC_ENCPER  = 0;
        private const int FUNC_OUTPUT  = 1;
        private const int FUNC_CONFIG  = 2;
        private const int FUNC_REQUEST = 3;
        private const int FUNC_STATUS  = 4;
        private const int FUNC_ENCRST  = 5;
        private const int FUNC_ENC     = 6;

        private ushort _channel = PCANBasic.PCAN_USBBUS1;
        private bool _connected = false;

        // controlli
        private ComboBox _cboChannel, _cboBaud;
        private NumericUpDown _numNode;
        private Button _btnConnect;
        private Label _lblConn;
        private TextBox _txtDir;
        private CheckBox[] _outBits = new CheckBox[32];
        private Panel[] _inBits = new Panel[32];
        private Label[] _encVals = new Label[8];
        private TextBox _txtPeriod;
        private TextBox _txtLog;
        private System.Windows.Forms.Timer _rxTimer;

        public MainForm()
        {
            Text = "CAN I/O Expander — Tester (PEAK PCAN-USB)";
            ClientSize = new Size(940, 760);
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            BuildUi();
            _rxTimer = new System.Windows.Forms.Timer { Interval = 20 };
            _rxTimer.Tick += RxTimer_Tick;
            FormClosing += (s, e) => Disconnect();
        }

        // ---------------------------------------------------------------- UI
        private void BuildUi()
        {
            // ---- Connessione ----
            var gConn = new GroupBox { Text = "Connessione", Location = new Point(10, 8), Size = new Size(920, 60) };
            _cboChannel = new ComboBox { Location = new Point(15, 24), Size = new Size(130, 24), DropDownStyle = ComboBoxStyle.DropDownList };
            for (int i = 1; i <= 8; i++) _cboChannel.Items.Add("PCAN-USB " + i);
            _cboChannel.SelectedIndex = 0;
            _cboBaud = new ComboBox { Location = new Point(155, 24), Size = new Size(110, 24), DropDownStyle = ComboBoxStyle.DropDownList };
            _cboBaud.Items.AddRange(new object[] { "500 kbit/s", "250 kbit/s", "125 kbit/s", "1 Mbit/s" });
            _cboBaud.SelectedIndex = 0;
            var lblNode = new Label { Text = "Nodo:", Location = new Point(280, 27), AutoSize = true };
            _numNode = new NumericUpDown { Location = new Point(325, 24), Size = new Size(50, 24), Minimum = 0, Maximum = 15, Value = 1 };
            _btnConnect = new Button { Text = "Connetti", Location = new Point(395, 23), Size = new Size(100, 26) };
            _btnConnect.Click += (s, e) => ToggleConnect();
            _lblConn = new Label { Text = "Disconnesso", Location = new Point(510, 27), AutoSize = true, ForeColor = Color.Firebrick };
            gConn.Controls.AddRange(new Control[] { _cboChannel, _cboBaud, lblNode, _numNode, _btnConnect, _lblConn });
            Controls.Add(gConn);

            // ---- Direzione (CONFIG) ----
            var gDir = new GroupBox { Text = "Direzione pin (CONFIG)  —  1 = uscita, 0 = ingresso", Location = new Point(10, 74), Size = new Size(920, 56) };
            var lblHex = new Label { Text = "Maschera (hex):", Location = new Point(15, 25), AutoSize = true };
            _txtDir = new TextBox { Location = new Point(120, 22), Size = new Size(110, 24), Text = "FFFF0000" };
            var btnDir = new Button { Text = "Imposta direzione", Location = new Point(245, 21), Size = new Size(140, 26) };
            btnDir.Click += (s, e) => { if (TryParseHex(_txtDir.Text, out uint m)) SendPinWord(FUNC_CONFIG, m, "CONFIG dir"); };
            var btnAllOut = new Button { Text = "Tutte uscite", Location = new Point(395, 21), Size = new Size(110, 26) };
            btnAllOut.Click += (s, e) => { _txtDir.Text = "FFFFFFFF"; SendPinWord(FUNC_CONFIG, 0xFFFFFFFF, "CONFIG dir"); };
            var btnAllIn = new Button { Text = "Tutti ingressi", Location = new Point(515, 21), Size = new Size(110, 26) };
            btnAllIn.Click += (s, e) => { _txtDir.Text = "00000000"; SendPinWord(FUNC_CONFIG, 0, "CONFIG dir"); };
            gDir.Controls.AddRange(new Control[] { lblHex, _txtDir, btnDir, btnAllOut, btnAllIn });
            Controls.Add(gDir);

            // ---- Uscite (OUTPUT) ----
            var gOut = new GroupBox { Text = "Uscite (OUTPUT)  —  spunta = livello alto", Location = new Point(10, 136), Size = new Size(920, 120) };
            BuildBitGrid(gOut, out _outBits);
            var btnWrite = new Button { Text = "Scrivi uscite", Location = new Point(770, 22), Size = new Size(130, 30) };
            btnWrite.Click += (s, e) => SendPinWord(FUNC_OUTPUT, ReadOutBits(), "OUTPUT");
            var btnClrOut = new Button { Text = "Azzera", Location = new Point(770, 58), Size = new Size(130, 26) };
            btnClrOut.Click += (s, e) => { foreach (var c in _outBits) c.Checked = false; SendPinWord(FUNC_OUTPUT, 0, "OUTPUT"); };
            gOut.Controls.AddRange(new Control[] { btnWrite, btnClrOut });
            Controls.Add(gOut);

            // ---- Ingressi / stato (STATUS) ----
            var gIn = new GroupBox { Text = "Stato pin (STATUS)  —  verde = alto", Location = new Point(10, 262), Size = new Size(920, 120) };
            BuildIndicatorGrid(gIn, out _inBits);
            var btnReq = new Button { Text = "Leggi stato", Location = new Point(770, 22), Size = new Size(130, 30) };
            btnReq.Click += (s, e) => SendRaw(FUNC_REQUEST, 0, new byte[0], 0, "REQUEST");
            gIn.Controls.Add(btnReq);
            Controls.Add(gIn);

            // ---- Encoder ----
            var gEnc = new GroupBox { Text = "Encoder incrementali (conteggi 16 bit con segno)", Location = new Point(10, 388), Size = new Size(920, 96) };
            for (int i = 0; i < 8; i++)
            {
                var cap = new Label { Text = "ENC" + i, Location = new Point(15 + i * 110, 22), AutoSize = true };
                _encVals[i] = new Label
                {
                    Text = "0",
                    Location = new Point(15 + i * 110, 42),
                    Size = new Size(90, 26),
                    BorderStyle = BorderStyle.FixedSingle,
                    TextAlign = ContentAlignment.MiddleCenter,
                    Font = new Font(FontFamily.GenericMonospace, 11, FontStyle.Bold)
                };
                gEnc.Controls.Add(cap);
                gEnc.Controls.Add(_encVals[i]);
            }
            var lblPer = new Label { Text = "Periodo (ms):", Location = new Point(15, 72), AutoSize = true };
            _txtPeriod = new TextBox { Location = new Point(110, 69), Size = new Size(60, 24), Text = "50" };
            var btnPer = new Button { Text = "Imposta periodo", Location = new Point(180, 68), Size = new Size(130, 26) };
            btnPer.Click += (s, e) => SetEncPeriod();
            var btnPerOff = new Button { Text = "Stop periodico", Location = new Point(320, 68), Size = new Size(120, 26) };
            btnPerOff.Click += (s, e) => { _txtPeriod.Text = "0"; SetEncPeriod(); };
            var btnEncRst = new Button { Text = "Azzera encoder", Location = new Point(450, 68), Size = new Size(130, 26) };
            btnEncRst.Click += (s, e) => { var d = new byte[8]; d[7] = 0xFF; SendRaw(FUNC_ENCRST, 0, d, 8, "ENC_RESET"); };
            gEnc.Controls.AddRange(new Control[] { lblPer, _txtPeriod, btnPer, btnPerOff, btnEncRst });
            Controls.Add(gEnc);

            // ---- Log ----
            var gLog = new GroupBox { Text = "Traffico CAN", Location = new Point(10, 490), Size = new Size(920, 258) };
            _txtLog = new TextBox
            {
                Location = new Point(12, 22),
                Size = new Size(896, 200),
                Multiline = true,
                ReadOnly = true,
                ScrollBars = ScrollBars.Vertical,
                Font = new Font(FontFamily.GenericMonospace, 9)
            };
            var btnClr = new Button { Text = "Pulisci", Location = new Point(808, 226), Size = new Size(100, 26) };
            btnClr.Click += (s, e) => _txtLog.Clear();
            gLog.Controls.Add(_txtLog);
            gLog.Controls.Add(btnClr);
            Controls.Add(gLog);
        }

        private void BuildBitGrid(Control parent, out CheckBox[] arr)
        {
            arr = new CheckBox[32];
            for (int i = 0; i < 32; i++)
            {
                int row = i / 16, col = i % 16;
                arr[i] = new CheckBox
                {
                    Text = i.ToString(),
                    Location = new Point(12 + col * 47, 22 + row * 44),
                    Size = new Size(45, 40),
                    Appearance = Appearance.Button,
                    TextAlign = ContentAlignment.MiddleCenter
                };
            }
            parent.Controls.AddRange(arr);
        }

        private void BuildIndicatorGrid(Control parent, out Panel[] arr)
        {
            arr = new Panel[32];
            for (int i = 0; i < 32; i++)
            {
                int row = i / 16, col = i % 16;
                var p = new Panel
                {
                    Location = new Point(12 + col * 47, 22 + row * 44),
                    Size = new Size(45, 40),
                    BorderStyle = BorderStyle.FixedSingle,
                    BackColor = Color.Gainsboro
                };
                var l = new Label { Text = i.ToString(), Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter };
                p.Controls.Add(l);
                arr[i] = p;
            }
            parent.Controls.AddRange(arr);
        }

        // ------------------------------------------------------ connessione
        private void ToggleConnect()
        {
            if (_connected) Disconnect();
            else Connect();
        }

        private void Connect()
        {
            _channel = (ushort)(PCANBasic.PCAN_USBBUS1 + _cboChannel.SelectedIndex);
            ushort baud = _cboBaud.SelectedIndex switch
            {
                1 => PCANBasic.PCAN_BAUD_250K,
                2 => PCANBasic.PCAN_BAUD_125K,
                3 => PCANBasic.PCAN_BAUD_1M,
                _ => PCANBasic.PCAN_BAUD_500K
            };
            TPCANStatus st;
            try
            {
                st = PCANBasic.Initialize(_channel, baud, 0, 0, 0);
            }
            catch (DllNotFoundException)
            {
                MessageBox.Show("PCANBasic.dll non trovato. Installa PCAN-Basic (PEAK) e copia il DLL x64 accanto all'eseguibile.",
                                "Errore", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            if (st != TPCANStatus.PCAN_ERROR_OK)
            {
                Log("Errore init: " + PCANBasic.ErrorText(st));
                MessageBox.Show("Inizializzazione fallita: " + PCANBasic.ErrorText(st), "Errore",
                                MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            _connected = true;
            _btnConnect.Text = "Disconnetti";
            _lblConn.Text = "Connesso";
            _lblConn.ForeColor = Color.ForestGreen;
            _rxTimer.Start();
            Log("Connesso su " + _cboChannel.Text + " a " + _cboBaud.Text);
        }

        private void Disconnect()
        {
            if (!_connected) return;
            _rxTimer.Stop();
            PCANBasic.Uninitialize(_channel);
            _connected = false;
            _btnConnect.Text = "Connetti";
            _lblConn.Text = "Disconnesso";
            _lblConn.ForeColor = Color.Firebrick;
            Log("Disconnesso");
        }

        // ------------------------------------------------------- invio CAN
        private byte Node => (byte)_numNode.Value;

        private void SendRaw(int func, int sub, byte[] data, int len, string tag)
        {
            if (!_connected) { Log("Non connesso"); return; }
            var msg = new TPCANMsg
            {
                ID = (uint)(((func & 0x7) << 8) | ((Node & 0xF) << 4) | (sub & 0xF)),
                MSGTYPE = (byte)TPCANMessageType.PCAN_MESSAGE_STANDARD,
                LEN = (byte)len,
                DATA = new byte[8]
            };
            for (int i = 0; i < len && i < 8; i++) msg.DATA[i] = data[i];
            var st = PCANBasic.Write(_channel, ref msg);
            Log(string.Format("TX 0x{0:X3} [{1}] {2}  {3}", msg.ID, len, HexBytes(msg.DATA, len), tag)
                + (st == TPCANStatus.PCAN_ERROR_OK ? "" : "  ERR: " + PCANBasic.ErrorText(st)));
        }

        private void SendPinWord(int func, uint word, string tag)
        {
            var d = new byte[4];
            d[0] = (byte)(word >> 24); d[1] = (byte)(word >> 16);
            d[2] = (byte)(word >> 8);  d[3] = (byte)word;
            SendRaw(func, 0, d, 4, tag + " 0x" + word.ToString("X8"));
        }

        private void SetEncPeriod()
        {
            if (!ushort.TryParse(_txtPeriod.Text, out ushort ms)) { Log("Periodo non valido"); return; }
            var d = new byte[] { (byte)(ms >> 8), (byte)ms };
            SendRaw(FUNC_ENCPER, 0, d, 2, "ENC_PERIOD " + ms + " ms");
        }

        private uint ReadOutBits()
        {
            uint w = 0;
            for (int i = 0; i < 32; i++) if (_outBits[i].Checked) w |= (1u << i);
            return w;
        }

        // ---------------------------------------------------- ricezione CAN
        private void RxTimer_Tick(object sender, EventArgs e)
        {
            if (!_connected) return;
            int guard = 0;
            TPCANStatus st;
            do
            {
                st = PCANBasic.Read(_channel, out TPCANMsg msg, out TPCANTimestamp _);
                if (st == TPCANStatus.PCAN_ERROR_OK) Process(msg);
            } while (st == TPCANStatus.PCAN_ERROR_OK && ++guard < 200);
        }

        private void Process(TPCANMsg msg)
        {
            bool ext = (msg.MSGTYPE & (byte)TPCANMessageType.PCAN_MESSAGE_EXTENDED) != 0;
            Log(string.Format("RX 0x{0:X3} [{1}] {2}{3}", msg.ID, msg.LEN, HexBytes(msg.DATA, msg.LEN), ext ? " (ext)" : ""));
            if (ext) return;

            int nd   = (int)((msg.ID >> 4) & 0xF);
            int func = (int)((msg.ID >> 8) & 0x7);
            if (nd != Node) return;

            if (func == FUNC_STATUS && msg.LEN >= 4)
            {
                uint inputs = ((uint)msg.DATA[0] << 24) | ((uint)msg.DATA[1] << 16)
                            | ((uint)msg.DATA[2] << 8)  |  (uint)msg.DATA[3];
                for (int i = 0; i < 32; i++)
                    _inBits[i].BackColor = ((inputs >> i) & 1) != 0 ? Color.LimeGreen : Color.Gainsboro;
            }
            else if (func == FUNC_ENC && msg.LEN >= 8)
            {
                int sub = (int)(msg.ID & 0xF);
                int baseIdx = (sub == 1) ? 4 : 0;
                for (int i = 0; i < 4; i++)
                {
                    short v = (short)((msg.DATA[2 * i] << 8) | msg.DATA[2 * i + 1]);
                    _encVals[baseIdx + i].Text = v.ToString();
                }
            }
        }

        // --------------------------------------------------------- utilita'
        private static bool TryParseHex(string s, out uint val)
        {
            s = (s ?? "").Trim();
            if (s.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) s = s.Substring(2);
            return uint.TryParse(s, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out val);
        }

        private static string HexBytes(byte[] d, int len)
        {
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < len && i < 8; i++) sb.Append(d[i].ToString("X2")).Append(' ');
            return sb.ToString().PadRight(24);
        }

        private void Log(string s)
        {
            string line = DateTime.Now.ToString("HH:mm:ss.fff") + "  " + s + Environment.NewLine;
            if (_txtLog.TextLength > 60000) _txtLog.Clear();
            _txtLog.AppendText(line);
        }
    }
}
