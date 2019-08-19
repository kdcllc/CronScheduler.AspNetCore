using System;
using System.Threading;
using System.Threading.Tasks;

using CronScheduler.AspNetCore;

using CronSchedulerApp.Services;

using Microsoft.Extensions.Options;

namespace CronSchedulerApp.Jobs
{
    public class TorahQuoteJob : IScheduledJob
    {
        private readonly TorahService _service;
        private readonly TorahSettings _options;
        private readonly TorahVerses _torahVerses;

        /// <summary>
        /// Initializes a new instance of the <see cref="TorahQuoteJob"/> class.
        /// </summary>
        /// <param name="options"></param>
        /// <param name="service"></param>
        /// <param name="torahVerses"></param>
        public TorahQuoteJob(
            IOptionsMonitor<TorahSettings> options,
            TorahService service,
            TorahVerses torahVerses)
        {
            _options = options.CurrentValue;
            CronSchedule = _options.CronSchedule; // set to 10 seconds in appsettings.json
            RunImmediately = _options.RunImmediately;
            CronTimeZone = _options.CronTimeZone;
            _service = service;
            _torahVerses = torahVerses;
        }

        public string CronSchedule { get; }

        public bool RunImmediately { get; }

        public string CronTimeZone { get; }

        public async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            var index = new Random().Next(_options.Verses.Length);
            var exp = _options.Verses[index];

            _torahVerses.Current = await _service.GetVersesAsync(exp, cancellationToken);
        }
    }
}
