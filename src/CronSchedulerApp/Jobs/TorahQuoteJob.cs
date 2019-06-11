using CronScheduler.AspNetCore;
using CronSchedulerApp.Services;
using Microsoft.Extensions.Options;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace CronSchedulerApp.Jobs
{
    public class TorahQuoteJob : IScheduledJob
    {
        public string CronSchedule { get; }

        public bool RunImmediately { get; }

        public string CronTimeZone { get; }

        private readonly TorahService _service;
        private readonly TorahSettings _options;
        private readonly TorahVerses _torahVerses;

        public TorahQuoteJob(
            IOptionsMonitor<TorahSettings> options,
            TorahService service,
            TorahVerses torahVerses)
        {
            _options = options.CurrentValue;
            CronSchedule = _options.CronSchedule; //set to 10 seconds in appsettings.json
            RunImmediately = _options.RunImmediately;
            CronTimeZone = _options.CronTimeZone;
            _service = service;
            _torahVerses = torahVerses;
        }

        public async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            var index = new Random().Next(_options.Verses.Length);
            var exp = _options.Verses[index];

            _torahVerses.Current = await _service.GetVersesAsync(exp, cancellationToken);
        }
    }
}
