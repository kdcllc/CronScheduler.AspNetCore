using System;
using System.Threading.Tasks;

using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Microsoft.Extensions.DependencyInjection
{
    public class SchedulerBuilder
    {
#pragma warning disable SA1401 // Fields should be private
#pragma warning disable CA1051 // Do not declare visible instance fields
        /// <summary>
        /// EventHanlder for Startup for Hosted Apps.
        /// </summary>
        public EventHandler<UnobservedTaskExceptionEventArgs> UnobservedTaskExceptionHandler;
#pragma warning restore CA1051 // Do not declare visible instance fields
#pragma warning restore SA1401 // Fields should be private

        public SchedulerBuilder(IServiceCollection services)
        {
            Services = services;
            Services.TryAddSingleton<ISchedulerRegistration, SchedulerRegistration>();
        }

        /// <summary>
        /// <see cref="IServiceCollection"/> for the DI.
        /// </summary>
        public IServiceCollection Services { get; }

        /// <summary>
        /// Adds Custom Named Job.
        /// </summary>
        /// <typeparam name="TJob">The type of the job.</typeparam>
        /// <param name="sectionName">The section for the job configurations.</param>
        /// <param name="namedJob">The name of the job.</param>
        /// <returns></returns>
        [Obsolete("This method will be depreciated in the next release.")]
        public IServiceCollection AddJob<TJob>(string sectionName = "SchedulerJobs", string? namedJob = null)
            where TJob : class, IScheduledJob
        {
            Services.AddSingleton<IScheduledJob, TJob>();

            var name = namedJob ?? typeof(TJob).Name;

            // named options used within the scheduler itself.
            Services.AddChangeTokenOptions<SchedulerOptions>($"{sectionName}:{typeof(TJob).Name}", name, _ => { });

            return Services;
        }

        [Obsolete("This method will be depreciated in the next release.")]
        public IServiceCollection AddJob<TJob>(Func<IServiceProvider, TJob> factory, string sectionName = "SchedulerJobs")
            where TJob : class, IScheduledJob
        {
            Services.AddSingleton(typeof(IScheduledJob), factory);

            var name = typeof(TJob).Name;

            // named options used within the scheduler itself.
            Services.AddChangeTokenOptions<SchedulerOptions>($"{sectionName}:{typeof(TJob).Name}", name, _ => { });

            return Services;
        }

        /// <summary>
        /// Adds <see cref="IScheduledJob"/> to DI with options.
        /// </summary>
        /// <typeparam name="TJob">The type of the job.</typeparam>
        /// <typeparam name="TJobOptions">The options for the job.</typeparam>
        /// <param name="sectionName"></param>
        /// <param name="namedJob">The name of the job, use this for options as well.</param>
        /// <returns></returns>
        public IServiceCollection AddJob<TJob, TJobOptions>(
            string sectionName = "SchedulerJobs",
            string? namedJob = null)
            where TJob : class, IScheduledJob
            where TJobOptions : SchedulerOptions, new()
        {
            var name = namedJob ?? typeof(TJob).Name;

            // named options used within the job.
            Services.AddChangeTokenOptions<TJobOptions>($"{sectionName}:{typeof(TJob).Name}");

            // named options used within the scheduler itself.
            Services.AddChangeTokenOptions<SchedulerOptions>($"{sectionName}:{typeof(TJob).Name}", name, _ => { });

            Services.AddSingleton<IScheduledJob, TJob>();

            return Services;
        }

        /// <summary>
        /// Adds options for the custom job.
        /// </summary>
        /// <typeparam name="TJob"></typeparam>
        /// <param name="sectionName"></param>
        /// <param name="configure"></param>
        /// <returns></returns>
        public IServiceCollection AddJobOptions<TJob>(
            string sectionName = "SchedulerJobs",
            Action<SchedulerOptions>? configure = null)
             where TJob : class, IScheduledJob
        {
            var name = typeof(TJob).Name;

            return AddJobOptions(name, $"{sectionName}:{name}", configure);
        }

        /// <summary>
        /// Add Jobs options based on the string name.
        /// </summary>
        /// <param name="namedJob">The named job.</param>
        /// <param name="sectionName">The section name.</param>
        /// <param name="configure">The custom options configuration.</param>
        /// <returns></returns>
        public IServiceCollection AddJobOptions(
            string namedJob,
            string sectionName,
            Action<SchedulerOptions>? configure = null)
        {
            return Services.AddChangeTokenOptions(sectionName, namedJob, configure);
        }
    }
}
