namespace CronScheduler.AspNetCore
{
    public class SchedulerOptions
    {
        /// <summary>
        /// Specify the CRON schedule.
        /// <see cref="!:https://github.com/HangfireIO/Cronos/blob/f512241dfc9a0acd65f835cb8f4eab91053efcd5/README.md#cron-format"/>.
        /// </summary>
        public string CronSchedule { get; set; }

        /// <summary>
        /// Time Zone for the Scheduler to run. Default is null, sets it to local time zone.
        /// Can be set to "Eastern Standard Time" or "Pacific Standard Time" etc.
        /// </summary>
        public string CronTimeZone { get; set; } = null;

        /// <summary>
        /// Specify if the Job to be run immediately. Default value is false.
        /// </summary>
        public bool RunImmediately { get; set; } = false;
    }
}
