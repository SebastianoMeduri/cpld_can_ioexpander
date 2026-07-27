using System;
using System.Drawing;
using System.Windows.Forms;

namespace ExpanderTester
{
    // Finestra di controllo per la variante motore (8 driver VNH7100AS).
    // Invia i comandi via la SendRaw della MainForm (delegate passato al costruttore).
    public class MotorForm : Form
    {
        private const int FUNC_MOTOR  = 1;   // slot OUTPUT = comando MOTOR
        private const int FUNC_CONFIG = 2;

        // send(func, sub, data, len, tag)
        private readonly Action<int, int, byte[], int, string> _send;

        private readonly ComboBox[] _mode = new ComboBox[8];
        private readonly NumericUpDown[] _duty = new NumericUpDown[8];
        private readonly Panel[] _oc = new Panel[8];   // lampada sovracorrente per motore
        private Label _alarm;                          // indicatore globale (= LED led_alarm)
        private ComboBox _safeMode;
        private CheckBox _sel0;

        public MotorForm(Action<int, int, byte[], int, string> send)
        {
            _send = send;
            Text = "Controllo motori (VNH7100AS)";
            ClientSize = new Size(560, 430);
            StartPosition = FormStartPosition.CenterParent;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false;
            BuildUi();
        }

        private void BuildUi()
        {
            var gMot = new GroupBox { Text = "Comando motori  —  duty 0..63 (63 = fondoscala = ON statico)", Location = new Point(10, 8), Size = new Size(540, 336) };
            gMot.Controls.Add(new Label { Text = "Motore",   Location = new Point(15, 24),  AutoSize = true });
            gMot.Controls.Add(new Label { Text = "Modalità", Location = new Point(75, 24),  AutoSize = true });
            gMot.Controls.Add(new Label { Text = "Duty",     Location = new Point(205, 24), AutoSize = true });
            gMot.Controls.Add(new Label { Text = "Fond.",    Location = new Point(280, 24), AutoSize = true });
            gMot.Controls.Add(new Label { Text = "Sovrac.",  Location = new Point(320, 24), AutoSize = true });

            for (int i = 0; i < 8; i++)
            {
                int y = 48 + i * 34;
                gMot.Controls.Add(new Label { Text = "M" + i, Location = new Point(20, y + 4), AutoSize = true });

                _mode[i] = new ComboBox { Location = new Point(70, y), Size = new Size(120, 24), DropDownStyle = ComboBoxStyle.DropDownList };
                _mode[i].Items.AddRange(new object[] { "Coast", "Avanti", "Indietro", "Brake" });
                _mode[i].SelectedIndex = 0;

                _duty[i] = new NumericUpDown { Location = new Point(200, y), Size = new Size(60, 24), Minimum = 0, Maximum = 63, Value = 0 };

                int idx = i;
                var chkFs = new CheckBox { Text = "", Location = new Point(288, y + 2), AutoSize = true };
                chkFs.CheckedChanged += (s, e) => { if (chkFs.Checked) _duty[idx].Value = 63; };

                _oc[i] = new Panel { Location = new Point(325, y), Size = new Size(20, 20), BorderStyle = BorderStyle.FixedSingle, BackColor = Color.Gainsboro };

                gMot.Controls.AddRange(new Control[] { _mode[i], _duty[i], chkFs, _oc[i] });
            }

            _alarm = new Label { Text = "● ALLARME MOTORI", Location = new Point(360, 30), AutoSize = true, ForeColor = Color.Gray, Font = new Font(FontFamily.GenericSansSerif, 10, FontStyle.Bold) };
            gMot.Controls.Add(_alarm);

            var btnSend = new Button { Text = "Invia comando motori", Location = new Point(360, 60), Size = new Size(160, 30) };
            btnSend.Click += (s, e) => SendMotors();
            var btnStop = new Button { Text = "STOP (tutti coast)", Location = new Point(360, 100), Size = new Size(160, 28) };
            btnStop.Click += (s, e) => { foreach (var c in _mode) c.SelectedIndex = 0; foreach (var d in _duty) d.Value = 0; SendMotors(); };
            gMot.Controls.AddRange(new Control[] { btnSend, btnStop });
            Controls.Add(gMot);

            var gCfg = new GroupBox { Text = "Configurazione", Location = new Point(10, 350), Size = new Size(540, 70) };
            gCfg.Controls.Add(new Label { Text = "Stato sicuro:", Location = new Point(15, 30), AutoSize = true });
            _safeMode = new ComboBox { Location = new Point(105, 27), Size = new Size(130, 24), DropDownStyle = ComboBoxStyle.DropDownList };
            _safeMode.Items.AddRange(new object[] { "Coast (ruota libera)", "Brake (frenata GND)" });
            _safeMode.SelectedIndex = 0;
            _sel0 = new CheckBox { Text = "SEL0 = 1", Location = new Point(250, 29), AutoSize = true };
            var btnCfg = new Button { Text = "Applica config", Location = new Point(360, 25), Size = new Size(160, 28) };
            btnCfg.Click += (s, e) => SendConfig();
            gCfg.Controls.AddRange(new Control[] { _safeMode, _sel0, btnCfg });
            Controls.Add(gCfg);
        }

        private void SendMotors()
        {
            var d = new byte[8];
            for (int i = 0; i < 8; i++)
            {
                int mode = _mode[i].SelectedIndex & 0x3;      // 0=coast,1=fwd,2=rev,3=brake
                int duty = (int)_duty[i].Value & 0x3F;
                d[i] = (byte)((mode << 6) | duty);
            }
            _send(FUNC_MOTOR, 0, d, 8, "MOTOR");
        }

        private void SendConfig()
        {
            byte b = 0;
            if (_safeMode.SelectedIndex == 1) b |= 0x01;   // brake
            if (_sel0.Checked) b |= 0x02;                  // SEL0
            _send(FUNC_CONFIG, 0, new byte[] { b }, 1, "CONFIG motore");
        }

        // Aggiorna gli indicatori di sovracorrente dal bitmap ANALOG SUB=2
        // (= LED led_alarm). Chiamata dalla MainForm alla ricezione della trama.
        public void UpdateAlarm(byte over)
        {
            _alarm.ForeColor = over != 0 ? Color.Red : Color.Gray;
            for (int i = 0; i < 8; i++)
                _oc[i].BackColor = ((over >> i) & 1) != 0 ? Color.Red : Color.Gainsboro;
        }
    }
}
