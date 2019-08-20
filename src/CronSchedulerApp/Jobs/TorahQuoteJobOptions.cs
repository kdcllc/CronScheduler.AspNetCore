using CronScheduler.AspNetCore;

namespace CronSchedulerApp.Jobs
{
    public class TorahQuoteJobOptions : SchedulerOptions
    {
        public string ApiUrl { get; set; }

        public string WebsiteUrl { get; set; }

        public string[] Verses { get; set; }
    }
}
