using CronScheduler.Extensions.Scheduler;

namespace CronSchedulerWorker
{
    public class TestJobOptions : SchedulerOptions
    {
        public string CustomField { get; set; } = string.Empty;
    }
}
