(function () {
    var $ = function (id) { return document.getElementById(id); };
    var bars = $('bars');
    for (var i = 0; i < 90; i++) bars.appendChild(document.createElement('i'));
    var nf = new Intl.NumberFormat('en-US');
    var text = { ok: 'No incidents', degraded: 'Degraded performance', outage: 'Service disruption' };

    function dayLabel(i) {
        var d = new Date();
        d.setUTCDate(d.getUTCDate() - (89 - i));
        return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
    }

    function load() {
        fetch('/api/status', { cache: 'no-store' })
            .then(function (r) { return r.json(); })
            .then(function (s) {
                $('uptime').textContent = s.uptime_90d.toFixed(2) + '%';
                $('streak').textContent = s.since_incident >= 90 ? '90+' : s.since_incident;
                $('probes').textContent = nf.format(s.probes);
                s.days.forEach(function (st, i) {
                    var el = bars.children[i];
                    el.className = st === 'ok' ? '' : st;
                    el.title = dayLabel(i) + ' · ' + text[st];
                });
            })
            .catch(function () {});
    }
    load();
    setInterval(load, 30000);

    var form = $('signup'), hint = $('hint'), btn = $('go');
    form.addEventListener('submit', function (e) {
        e.preventDefault();
        var email = $('email').value.trim();
        btn.disabled = true;
        hint.className = 'hint';
        hint.textContent = 'Sending…';
        fetch('/api/subscribe', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email: email })
        })
            .then(function (r) { return r.json().then(function (d) { return { ok: r.ok, d: d }; }); })
            .then(function (x) {
                if (x.ok) {
                    hint.className = 'hint ok';
                    hint.textContent = 'We’ve sent a sign-in link to ' + email + '. It expires in 15 minutes.';
                    form.reset();
                } else {
                    hint.className = 'hint err';
                    hint.textContent = x.d.error || 'Something went wrong. Please try again.';
                }
            })
            .catch(function () {
                hint.className = 'hint err';
                hint.textContent = 'Network error. Please try again.';
            })
            .then(function () { btn.disabled = false; });
    });
})();
