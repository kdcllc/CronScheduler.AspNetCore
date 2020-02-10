using System;

using CronScheduler.Extensions.Scheduler;

namespace CronSchedulerApp.Jobs
{
    public class TorahQuoteJobOptions : SchedulerOptions
    {
        public string ApiUrl { get; set; } = string.Empty;

        public string WebsiteUrl { get; set; } = string.Empty;

        public string[] Verses { get; set; } = Array.Empty<string>();
    }
}
