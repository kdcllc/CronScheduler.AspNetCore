using System;
using System.Threading;
using System.Threading.Tasks;
using CronScheduler.AspNetCore;
using Microsoft.Extensions.Options;
using CronSchedulerApp.Services;

namespace CronSchedulerApp.Jobs
{
    public class TorahQuoteJob : IScheduledJob
    {
        public string CronSchedule { get; }

        public bool RunImmediately { get; }

        public string CronTimeZone { get; }

        private readonly TorahService _service;
        private readonly TorahSettings _options;

        public TorahQuoteJob(
            IOptions<TorahSettings> options,
            TorahService service)
        {
            _options = options.Value;
            CronSchedule = _options.CronSchedule; //set to 10 seconds in appsettings.json
            RunImmediately = _options.RunImmediately;
            CronTimeZone = _options.CronTimeZone;
            _service = service;
        }

        public async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            var index = new Random().Next(_options.Verses.Length);
            var exp = _options.Verses[index];

            var result = await _service.GetVersesAsync(exp, cancellationToken);

            TorahVerses.Current = result;
        }
    }
}
