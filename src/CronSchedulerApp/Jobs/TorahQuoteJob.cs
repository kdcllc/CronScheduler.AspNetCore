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

        private readonly TorahService _service;
        private readonly TorahSettings _options;

        public TorahQuoteJob(IOptions<TorahSettings> options, TorahService service)
        {
            _options = options.Value;
            CronSchedule = _options.CronSchedule; //set to 1 min in appsettings.json
            RunImmediately = true;
            _service = service;
        }

        public async Task ExecuteAsync(CancellationToken cancellationToken)
        {
            var index = new Random().Next(_options.Verses.Length);
            var exp = _options.Verses[index];

            var result = await _service.GetVerses(exp, cancellationToken);

            TorahVerses.Current = result;
        }
    }
}
