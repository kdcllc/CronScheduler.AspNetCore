using System;

namespace CronScheduler.Extensions.BackgroundTask
{
    /// <summary>
    /// The basic options for the <see cref="QueuedHostedService"/>.
    /// </summary>
    public class QueuedHostedServiceOptions
    {
        /// <summary>
        /// The <see cref="TimeSpan"/> to wait before gracefully shutdown the application.
        /// </summary>
        public TimeSpan ApplicationOnStopWaitTimeout { get; set; }

        /// <summary>
        /// The flag to enable or disable the wait for the BackgroundTasks to be completed before allowing the application to shutdown.
        /// </summary>
        public bool EnableApplicationOnStopWait { get; set; }
    }
}
