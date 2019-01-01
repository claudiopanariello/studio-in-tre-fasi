// =====================================================================
// cla.panariello@gmail.com
//
// I solenoidi seguono delle regole dettate da algoritmi del tipo di prossimità
// Li muovo ad archi, cioè divido le 11 coppie di solenoidi.
// L'Arduino ~uno controlla i primi 12 solenoidi (0..11), collegati ai pin 2-13;
// l'Arduino ~due controlla i restanti 10 solenoidi (12..21), collegati ai pin 2-11.
// Vengono attivati da un monitoraggio del segnale in ingresso e seguono in ogni caso delle regole di feedback negativo:
//            - ampiezza in ingresso elevata, i solenoidi tacciono o comunque si fanno più diradati;
//            - ampiezza in ingresso ridotta, i solenoidi vengono attivati.
//
// Se l'ampiezza rimane per un certo lasso di tempo sopra o sotto una certa soglia, viene attivata una sequenza "ordinata"
// scollegata dall'ambiente. Al suo termine si ritorna a muovere i solenoidi in funzione degli eventi esterni.
//
// Selezionare tutto e farlo andare. (cmd+a, cmd+enter)
//
// NOTA BENE:
//     - Assicurarsi che sugli Arduino sia stato caricato lo sketch per la corretta interpretazione dei byte.
//     - Notare che le uscite 0 e 1 dell'Arduino sono transmitter e receiver, quindi uso le uscite da 2 a 13.
//
// =====================================================================

//SerialPort.devices;

s.options.memSize=2.pow(19); // <<<---------
s.waitForBoot({
	// Apro le porte seriali per mandare e ricevere dagli Srduino
	(
		~uno = ArduinoSMS("/dev/tty.usbmodemfa2441", 115200);
		~due = ArduinoSMS("/dev/tty.usbmodemfd1441", 115200);

		// read digital inputs
		//~uno.send($r, $d);
		//~due.send($r, $d);
		// read analog inputs
		//~uno.send($r, $a);
		//~due.send($r, $a);
	);
	(
		~input = Bus.audio(s, 1);
		~busenv = Bus.audio(s, 1);
		SynthDef(\input,
			{
				arg gain = 10, lag = 0.5, lagTime = 1;
				var in, rms, control, amp;
				in = SoundIn.ar(0);//un microfono solo - prova dal mic del compter
				//in = Mix.ar([SoundIn.ar(0), SoundIn.ar(1)]); //mix dei due input microfonici
				rms = RunningSum.rms(Amplitude.ar(in)).clip(0, 1);
				amp = Lag.ar(rms, lagTime);
				control = 1 -(rms.lag2(lag));
				SendReply.kr(Impulse.kr(20), '/amp_input', amp); //ampiezza input
				Out.ar(~input, in*gain*control);
		}).send(s);

		SynthDef(\nigredo,
			{
				arg lag = 0.5, freq, thresh, maxdelay = 5.0, delay, rq, lagTime, band_num, level = 1;
				var
				in = In.ar(~input, 1),
				filter = BPF.ar(in, freq, rq, level),
				out = DelayL.ar(filter, maxdelay, delay),
				amp = Lag3.ar(Amplitude.ar(out).linlin(0.0001, 1, 0, 1), lagTime),
				control = 1 -(amp),
				trig = amp > thresh,
				timeTrig = Trig1.ar((Timer.ar(trig) > 0.5)*trig, 0.2); //per escludere i trigger nei 0.5 secondi successivi
				SendReply.kr(Impulse.kr(20), '/banda', amp, band_num); //ampiezza delle bande
				SendReply.kr(Impulse.kr(20), '/trig', timeTrig, band_num); //trigger sulle bande
		}).send(s);
	);
	1.wait;
	(
		~size = 11; //coppie di solenoidi
		~synths = Array.fill(~size, 0); //array dei miei Synth
		~thresh = Array.fill(11, {|n| (1-sin(n*pi/10))}).linlin(0, 1, 0.1, 0.2); //array dei threshold
		~bandosc = Array.fill(~size, 0); //array dei SendReply per monitorare le ampiezze delle bande
		~trigosc = Array.fill(~size, 0); //array dei SendReply per i trigger
		~freqs = Array.fill(~size, {|i| i}).linexp(0, ~size-1, 40, 10000); //array delle frequenze di centro banda
		~delays = Array.fill(~size, {rrand(0, 5.0)}); //array dei delay
		~amp_input = 0;
		~size.do({|i| ~synths[i] = Synth(\nigredo, [\thresh, ~thresh[i], \rq, 0.5, \freq, ~freqs[i], \delay, ~delays[i], \lagTime, 0.5, \band_num, i, \level, 10])});

		~input = Synth(\input, [\gain, 2]);

		w = Window("Tre Fasi", Rect(300, 200, 600, 700)).front.background_(Color.white);
		z = w.addFlowLayout;

		//Indicatore dell'ampiezza in ingresso
		~ampiezza = EZSlider(w, 500@25, "Ampiezza IN ", [0, 1, 'lin', 0.001].asSpec, initAction: true, layout: 'horz', labelWidth: 90).adaptToControlStep;
		~ampiezza.setColors(Color.grey, Color.white);
		OSCFunc({|msg| ~amp_input = msg[3].value; {~ampiezza.value_(msg[3].value)}.defer}, '/amp_input');
		z.nextLine;

		//Multislider
		StaticText(w, 300@30).string_("Ampiezze rilevate sulle bande (con un Lag)");
		~panamulti = MultiSliderView(w, Rect(0, 0, 400, 200));
		StaticText(w, 200@30).string_("Delay sul rilevamento");
		n = MultiSliderView(w, Rect(-350, 0, 400, 200));

		n.value_(Array.fill(~size, {|i| ~delays[i]/5}));

		~panamulti.isFilled_(true); // width in pixels of each stick
		~panamulti.indexThumbSize_(12.5); // spacing on the value axis
		n.indexThumbSize_(12.5);
		~panamulti.showIndex_(true);
		n.showIndex_(true);
		~panamulti.gap_(5);
		n.gap_(5);
		z.nextLine;
		//NumberBox per il conteggio degli shift
		~shift_num = EZNumber(w, 120@20, "Shift", [0, inf, 'lin', 1].asSpec);

		//Ogni timewait secondi faccio uno shift a sinistra di tutte le bande.
		//Dopo (timewait*11) secondi sarò tornato alla situazione di partenza
		Task({
			var timewait = 10,
			j =0;
			inf.do({
				~bandosc = Array.fill(~size, 0);
				~panaosc = OSCFunc({|msg| ~bandosc[(msg[2].value - j)%~size] = msg[3].value}, '/banda');
				~panatrig = OSCFunc({|msg| ~trigosc[(msg[2].value - j)%~size] = msg[3].value}, '/trig');
				{~shift_num.value_(j%~size);}.defer;
				timewait.wait;
				j = j+1;
				~panaosc.free;
				~panatrig.free;
			})
		}).start;

		// Questo è il task per far muovere il multislider che tiene traccia delle ampiezze rilevate sulle varie bande
		Task({
			inf.do({
				~panamulti.value_(~bandosc);
				//~trigosc[5].postln;
				//~amp_input.postln;
				0.1.wait;
			});
		}).play(AppClock);

		//Solenoidi
		~sol = Array.fill(~size*2, 0); //array (size*2) elementi per i solenoidi
		(~size*2).do{|i|
			if(i%2 == 0,
				{z.top_(20*(i+1)+50); z.left_(430);},    //posizione dei solenoidi sulla GUI
				{z.top_(20*i +50); z.left_(500);});
			z.gap_(10@10);
			~sol[i] = Button(w, 50@20).states_([[i, Color.black, Color.white],[i, Color.black, Color.gray]]);
		};

		////////////////////////////////////////////////////////////////////////////////////////////////////////////

		~panapiece = false;
		~panarithm = Array.fill(22, {|i| 0.005*i + 0.1});

		//NumberBox per il conteggio dei secondi per il ~panapiece
		( z.top_(530);
			~secondsNumber = EZNumber(w, 120@20, "Timer", [0, inf, 'lin', 0.01].asSpec);
			StaticText(w, 175@30).string_("se > 5 secondi allora True.");
			~pieceButton = Button(w, 75@25).states_([["False", Color.black, Color.red],["True", Color.black, Color.green]]);
		);
		~soglia_inf = 0;
		~soglia_sup = 0;
		z.nextLine;
		EZNumber(w, 170@20, "Soglia inf *1e-4", [0, inf, 'lin', 1].asSpec,
			{|v| ~soglia_inf = v.value*1e-4; ("Soglia inferiore = "++~soglia_inf).postln;}, 5, true, labelWidth: 100, labelHeight: 40);
		EZNumber(w, 170@20, "Soglia sup *1e-4", [0, inf, 'lin', 1].asSpec,
			{|v| ~soglia_sup = v.value*1e-4; ("Soglia superiore = "++~soglia_sup).postln;}, 2000, true, labelWidth: 110, labelHeight: 40);

		//Questo è il task per far partire la composizione.
		//Se l'ampiezza va al di sotto di soglia_min o soglia_max conto il tempo in cui rimane in quel range.
		//Se vi rimane per più di *timeTrig* allora faccio partire il "task ordinato" settando la variabile ~panapiece = true.
		//Quando questo parte, il controllo dell'ampiezza (nonché tutti i task successivi) sono inibiti e
		//ritornano a funzionare solo al termine del task ordinato.
		//
		Task({
			var seconds = 0;
			inf.do({
				{~secondsNumber.value_(seconds);}.defer;
				{~pieceButton.value_(~panapiece)}.defer;
				if(((~amp_input < ~soglia_inf)||(~amp_input > ~soglia_sup))&&(~panapiece == false),
					//if((~amp_input > soglia_max)&&(~panapiece == false),
					{seconds = seconds + 0.01;
						if(seconds > 5,               // tempo di attesa
							{~panapiece = true;});},
					{seconds = 0;});
				0.01.wait;
			});
		}).start;

		// Muovo i solenoidi
		//ARCO 0
		Task({
			var result = [0], gen = 0;
			inf.do({
				var new, aux, lun;
				if((~trigosc[0] == 1) && (~panapiece == false), {
					new = [];
					i = 0;
					lun = result.size;
					aux = Array.newClear(lun);
					lun.do{|i| aux[i] = result[i]};
					if(lun > 10, {new = new.scramble.keep(2); lun = 2;});
					if (gen < 5, {
						while({i < lun},
							{
								if(aux[i] == 0, {new = new ++ [1, 0]});
								if(aux[i] == 1, {new = new ++ [0]});
								i = i + 1;
					})},
					{
						while({i < lun},
							{
								new = new ++ [20, 21, 0, 1, 2, 3].choose;
								i = i + 1;
					})}
					);
					gen = gen+1;
					result = new;
					result.postln;
					result.size.do{|n|
						if(new[n]-12<0,
							{~uno.send($w, $d, new[n]+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~uno.send($w, $d, new[n]+2, 0); {~sol[new[n]].value_(0)}.defer;},
							{~due.send($w, $d, new[n]%2+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~due.send($w, $d, new[n]%2+2, 0); {~sol[new[n]].value_(0)}.defer;});
						rrand(0.2, 0.7).wait
				};});
				0.2.wait;
			});
		}).start;

		// ARCO 1
		Task({
			var result = [2], gen = 0;
			inf.do({
				var new, aux, lun;
				if((~trigosc[1] == 1) && (~panapiece == false), {
					new = [];
					i = 0;
					lun = result.size;
					aux = Array.newClear(lun);
					lun.do{|i| aux[i] = result[i]};
					if(lun > 10, {new = new.scramble.keep(2); lun = 2;});
					if (gen < 5, {
						while({i < lun},
							{
								if(aux[i] == 2, {new = new ++ [2, 3, 2]});
								if(aux[i] == 3, {new = new ++ [3, 2]});
								i = i + 1;
					})},
					{
						while({i < lun},
							{
								new = new ++ (0..5).choose;
								i = i + 1;
					})}
					);
					gen = gen+1;
					result = new;
					result.postln;
					result.size.do{|n|
						if(new[n]-12<0,
							{~uno.send($w, $d, new[n]+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~uno.send($w, $d, new[n]+2, 0); {~sol[new[n]].value_(0)}.defer;},
							{~due.send($w, $d, new[n]%2+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~due.send($w, $d, new[n]%2+2, 0); {~sol[new[n]].value_(0)}.defer;});
						rrand(0.2, 0.7).wait
				};});
				0.2.wait;
			});
		}).start;

		// ARCO 2
		Task({
			var result = [4], gen = 0;
			inf.do({
				var new, aux, lun;
				if((~trigosc[2] == 1) && (~panapiece == false), {
					new = [];
					i = 0;
					lun = result.size;
					aux = Array.newClear(lun);
					lun.do{|i| aux[i] = result[i]};
					if(lun > 10, {new = new.scramble.keep(2); lun = 2;});
					if (gen < 5, {
						while({i < lun},
							{
								if(aux[i] == 4, {new = new ++ [5]});
								if(aux[i] == 5, {new = new ++ [4, 4, 5]});
								i = i + 1;
					})},
					{
						while({i < lun},
							{
								new = new ++ (2..7).choose;
								i = i + 1;
					})}
					);
					gen = gen+1;
					result = new;
					result.postln;
					result.size.do{|n|
						if(new[n]-12<0,
							{~uno.send($w, $d, new[n]+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~uno.send($w, $d, new[n]+2, 0); {~sol[new[n]].value_(0)}.defer;},
							{~due.send($w, $d, new[n]%2+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~due.send($w, $d, new[n]%2+2, 0); {~sol[new[n]].value_(0)}.defer;});
						rrand(0.2, 0.7).wait
				};});
				0.2.wait;
			});
		}).start;

		// ARCO 3
		Task({
			var result = [6], gen = 0;
			inf.do({
				var new, aux, lun;
				if((~trigosc[3] == 1) && (~panapiece == false), {
					new = [];
					i = 0;
					lun = result.size;
					aux = Array.newClear(lun);
					lun.do{|i| aux[i] = result[i]};
					if(lun > 10, {new = new.scramble.keep(2); lun = 2;});
					if (gen < 5, {
						while({i < lun},
							{
								if(aux[i] == 6, {new = new ++ [7, 7, 6]});
								if(aux[i] == 7, {new = new ++ [6]});
								i = i + 1;
					})},
					{
						while({i < lun},
							{
								new = new ++ (4..9).choose;
								i = i + 1;
					})}
					);
					gen = gen+1;
					result = new;
					result.postln;
					result.size.do{|n|
						if(new[n]-12<0,
							{~uno.send($w, $d, new[n]+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~uno.send($w, $d, new[n]+2, 0); {~sol[new[n]].value_(0)}.defer;},
							{~due.send($w, $d, new[n]%2+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~due.send($w, $d, new[n]%2+2, 0); {~sol[new[n]].value_(0)}.defer;});
						rrand(0.2, 0.7).wait
				};});
				0.2.wait;
			});
		}).start;

		// ARCO 4
		Task({
			var result = [8], gen = 0;
			inf.do({
				var new, aux, lun;
				if((~trigosc[4] == 1) && (~panapiece == false), {
					new = [];
					i = 0;
					lun = result.size;
					aux = Array.newClear(lun);
					lun.do{|i| aux[i] = result[i]};
					if(lun > 10, {new = new.scramble.keep(2); lun = 2;});
					if (gen < 5, {
						while({i < lun},
							{
								if(aux[i] == 8, {new = new ++ [9]});
								if(aux[i] == 9, {new = new ++ [9, 8]});
								i = i + 1;
					})},
					{
						while({i < lun},
							{
								new = new ++ (6..11).choose;
								i = i + 1;
					})}
					);
					gen = gen+1;
					result = new;
					result.postln;
					result.size.do{|n|
						if(new[n]-12<0,
							{~uno.send($w, $d, new[n]+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~uno.send($w, $d, new[n]+2, 0); {~sol[new[n]].value_(0)}.defer;},
							{~due.send($w, $d, new[n]%2+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~due.send($w, $d, new[n]%2+2, 0); {~sol[new[n]].value_(0)}.defer;});
						rrand(0.2, 0.7).wait
				};});
				0.2.wait;
			});
		}).start;

		// ARCO 5
		Task({
			var result = [10], gen = 0;
			inf.do({
				var new, aux, lun;
				if((~trigosc[5] == 1) && (~panapiece == false), {
					new = [];
					i = 0;
					lun = result.size;
					aux = Array.newClear(lun);
					lun.do{|i| aux[i] = result[i]};
					if(lun > 10, {new = new.scramble.keep(2); lun = 2;});
					if (gen < 5, {
						while({i < lun},
							{
								if(aux[i] == 10, {new = new ++ [10, 11]});
								if(aux[i] == 11, {new = new ++ [10]});
								i = i + 1;
					})},
					{
						while({i < lun},
							{
								new = new ++ (8..13).choose;
								i = i + 1;
					})}
					);
					gen = gen+1;
					result = new;
					result.postln;
					result.size.do{|n|
						if(new[n]-12<0,
							{~uno.send($w, $d, new[n]+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~uno.send($w, $d, new[n]+2, 0); {~sol[new[n]].value_(0)}.defer;},
							{~due.send($w, $d, new[n]%2+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~due.send($w, $d, new[n]%2+2, 0); {~sol[new[n]].value_(0)}.defer;});
						rrand(0.2, 0.7).wait
				};});
				0.2.wait;
			});
		}).start;

		// ARCO 6
		Task({
			var result = [12], gen = 0;
			inf.do({
				var new, aux, lun;
				if((~trigosc[6] == 1) && (~panapiece == false), {
					new = [];
					i = 0;
					lun = result.size;
					aux = Array.newClear(lun);
					lun.do{|i| aux[i] = result[i]};
					if(lun > 10, {new = new.scramble.keep(2); lun = 2;});
					if (gen < 5, {
						while({i < lun},
							{
								if(aux[i] == 12, {new = new ++ [13, 12]});
								if(aux[i] == 13, {new = new ++ [12, 13]});
								i = i + 1;
					})},
					{
						while({i < lun},
							{
								new = new ++ (10..15).choose;
								i = i + 1;
					})}
					);
					gen = gen+1;
					result = new;
					result.postln;
					result.size.do{|n|
						if(new[n]-12<0,
							{~uno.send($w, $d, new[n]+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~uno.send($w, $d, new[n]+2, 0); {~sol[new[n]].value_(0)}.defer;},
							{~due.send($w, $d, new[n]%2+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~due.send($w, $d, new[n]%2+2, 0); {~sol[new[n]].value_(0)}.defer;});
						rrand(0.2, 0.7).wait
				};});
				0.2.wait;
			});
		}).start;

		// ARCO 7
		Task({
			var result = [14], gen = 0;
			inf.do({
				var new, aux, lun;
				if((~trigosc[7] == 1) && (~panapiece == false), {
					new = [];
					i = 0;
					lun = result.size;
					aux = Array.newClear(lun);
					lun.do{|i| aux[i] = result[i]};
					if(lun > 10, {new = new.scramble.keep(2); lun = 2;});
					if (gen < 5, {
						while({i < lun},
							{
								if(aux[i] == 14, {new = new ++ [15]});
								if(aux[i] == 15, {new = new ++ [15, 14]});
								i = i + 1;
					})},
					{
						while({i < lun},
							{
								new = new ++ (12..17).choose;
								i = i + 1;
					})}
					);
					gen = gen+1;
					result = new;
					result.postln;
					result.size.do{|n|
						if(new[n]-12<0,
							{~uno.send($w, $d, new[n]+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~uno.send($w, $d, new[n]+2, 0); {~sol[new[n]].value_(0)}.defer;},
							{~due.send($w, $d, new[n]%2+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~due.send($w, $d, new[n]%2+2, 0); {~sol[new[n]].value_(0)}.defer;});
						rrand(0.2, 0.7).wait
				};});
				0.2.wait;
			});
		}).start;

		// ARCO 8
		Task({
			var result = [16], gen = 0;
			inf.do({
				var new, aux, lun;
				if((~trigosc[8] == 1) && (~panapiece == false), {
					new = [];
					i = 0;
					lun = result.size;
					aux = Array.newClear(lun);
					lun.do{|i| aux[i] = result[i]};
					if(lun > 10, {new = new.scramble.keep(2); lun = 2;});
					if (gen < 5, {
						while({i < lun},
							{
								if(aux[i] == 16, {new = new ++ [17, 16, 17]});
								if(aux[i] == 17, {new = new ++ [17, 16]});
								i = i + 1;
					})},
					{
						while({i < lun},
							{
								new = new ++ (14..19).choose;
								i = i + 1;
					})}
					);
					gen = gen+1;
					result = new;
					result.postln;
					result.size.do{|n|
						if(new[n]-12<0,
							{~uno.send($w, $d, new[n]+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~uno.send($w, $d, new[n]+2, 0); {~sol[new[n]].value_(0)}.defer;},
							{~due.send($w, $d, new[n]%2+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~due.send($w, $d, new[n]%2+2, 0); {~sol[new[n]].value_(0)}.defer;});
						rrand(0.2, 0.7).wait
				};});
				0.2.wait;
			});
		}).start;

		// ARCO 9
		Task({
			var result = [18], gen = 0;
			inf.do({
				var new, aux, lun;
				if((~trigosc[9] == 1) && (~panapiece == false), {
					new = [];
					i = 0;
					lun = result.size;
					aux = Array.newClear(lun);
					lun.do{|i| aux[i] = result[i]};
					if(lun > 10, {new = new.scramble.keep(2); lun = 2;});
					if (gen < 5, {
						while({i < lun},
							{
								if(aux[i] == 18, {new = new ++ [19]});
								if(aux[i] == 19, {new = new ++ [18, 18, 19]});
								i = i + 1;
					})},
					{
						while({i < lun},
							{
								new = new ++ (16..21).choose;
								i = i + 1;
					})}
					);
					gen = gen+1;
					result = new;
					result.postln;
					result.size.do{|n|
						if(new[n]-12<0,
							{~uno.send($w, $d, new[n]+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~uno.send($w, $d, new[n]+2, 0); {~sol[new[n]].value_(0)}.defer;},
							{~due.send($w, $d, new[n]%2+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~due.send($w, $d, new[n]%2+2, 0); {~sol[new[n]].value_(0)}.defer;});
						rrand(0.2, 0.7).wait
				};});
				0.2.wait;
			});
		}).start;

		// ARCO 10
		Task({
			var result = [20], gen = 0;
			inf.do({
				var new, aux, lun;
				if((~trigosc[10] == 1) && (~panapiece == false), {
					new = [];
					i = 0;
					lun = result.size;
					aux = Array.newClear(lun);
					lun.do{|i| aux[i] = result[i]};
					if(lun > 10, {new = new.scramble.keep(2); lun = 2;});
					if (gen < 5, {
						while({i < lun},
							{
								if(aux[i] == 20, {new = new ++ [21, 21, 20]});
								if(aux[i] == 21, {new = new ++ [20]});
								i = i + 1;
					})},
					{
						while({i < lun},
							{
								new = new ++ [18, 19, 20, 21, 0, 1].choose;
								i = i + 1;
					})}
					);
					gen = gen+1;
					result = new;
					result.postln;
					result.size.do{|n|
						if(new[n]-12<0,
							{~uno.send($w, $d, new[n]+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~uno.send($w, $d, new[n]+2, 0); {~sol[new[n]].value_(0)}.defer;},
							{~due.send($w, $d, new[n]%2+2, 1); {~sol[new[n]].value_(1)}.defer; 0.07.wait; ~due.send($w, $d, new[n]%2+2, 0); {~sol[new[n]].value_(0)}.defer;});
						rrand(0.2, 0.7).wait
				};});
				0.2.wait;
			});
		}).start;

		// TASK ORDINATO che parte se la ~panapiece è vera.
		//Al suo termine la variabile ~panapiece viene settata false
		22.do({|n|
			var rit =0;
			Task({
				var solen = n;
				inf.do({
					if (~panapiece == true, {
						if(new[n]-12<0,
							{~uno.send($w, $d, solen+2, 1); {~sol[solen].value_(1)}.defer; 0.07.wait; ~uno.send($w, $d, solen+2, 0); {~sol[solen].value_(0)}.defer;},
							{~due.send($w, $d, solen%2+2, 1); {~sol[solen].value_(1)}.defer; 0.07.wait; ~due.send($w, $d, solen%2+2, 0); {~sol[solen].value_(0)}.defer;});
						if(rit < 21,
							{rit = (rit + 1); ~panarithm.rotate(n)[rit].wait;},
							{~panapiece = false; rit = 0;}
						);
					});
					1.wait;
				});
			}).start;
		});

		w.onClose_({s.freeAll;})
	)
})

// EOF