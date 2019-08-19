using CronScheduler.AspNetCore;

namespace CronSchedulerApp.Services
{
    public class TorahSettings : SchedulerOptions
    {
        public string ApiUrl { get; set; }

        public string WebsiteUrl { get; set; }

        public string[] Verses { get; set; }
    }
}
