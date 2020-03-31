using System.Collections.Generic;

using CronScheduler.Extensions.Internal;

namespace CronScheduler.Extensions.Scheduler
{
    /// <summary>
    /// Scheduled Jobs Registration.
    /// </summary>
    public interface ISchedulerRegistration
    {
        IReadOnlyDictionary<string, SchedulerTaskWrapper> Jobs { get; }

        /// <summary>
        /// Add or Update existing job. This methods requires that Options are registered for the job.
        /// </summary>
        /// <param name="jobName">The name of the job.</param>
        /// <param name="job">The instance of the custom job.</param>
        /// <returns></returns>
        bool AddOrUpdate(string jobName, IScheduledJob job);

        /// <summary>
        /// Add or Update existing job. This methods requires that Options are registered for the job.
        /// </summary>
        /// <param name="job">The instance of the custom job.</param>
        /// <returns></returns>
        bool AddOrUpdate(IScheduledJob job);

        /// <summary>
        /// Add or Update an existing custom job. This method doesn't rely on the registered options.
        /// </summary>
        /// <param name="jobName">The name of the job.</param>
        /// <param name="job">The instance of the custom job.</param>
        /// <param name="options">The options to be configured for the named job.</param>
        /// <returns></returns>
        bool AddOrUpdate(string jobName, IScheduledJob job, SchedulerOptions options);

        /// <summary>
        /// Add or Update an existing custom job. This method doesn't rely on the registered options.
        /// </summary>
        /// <param name="job">The instance of the custom job.</param>
        /// <param name="options"></param>
        /// <returns></returns>
        bool AddOrUpdate(IScheduledJob job, SchedulerOptions options);

        /// <summary>
        /// Remove job by name.
        /// </summary>
        /// <param name="jobName"></param>
        /// <returns></returns>
        bool Remove(string jobName);
    }
}
