using CronScheduler.Extensions.Scheduler;

namespace CronScheduler.UnitTest
{
    public class CustomTestJobOptions : SchedulerOptions
    {
        public string DisplayText { get; set; } = string.Empty;
    }
}
