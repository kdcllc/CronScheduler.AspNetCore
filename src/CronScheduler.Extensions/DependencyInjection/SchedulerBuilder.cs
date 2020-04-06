using System;
using System.Threading.Tasks;

using CronScheduler.Extensions.Internal;
using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;

namespace Microsoft.Extensions.DependencyInjection
{
    public class SchedulerBuilder
    {
        /// <summary>
        /// EventHanlder for Startup for Hosted Apps.
        /// </summary>
#pragma warning disable CA1051 // Do not declare visible instance fields
#pragma warning disable SA1401 // Fields should be private
        public EventHandler<UnobservedTaskExceptionEventArgs>? UnobservedTaskExceptionHandler;
#pragma warning restore SA1401 // Fields should be private
#pragma warning restore CA1051 // Do not declare visible instance fields

        /// <summary>
        /// Initializes a new instance of the <see cref="SchedulerBuilder"/> class.
        /// </summary>
        /// <param name="services"></param>
        public SchedulerBuilder(IServiceCollection services)
        {
            Services = services ?? throw new ArgumentNullException(nameof(services));
            Services.TryAddSingleton<ISchedulerRegistration, SchedulerRegistration>();
        }

        /// <summary>
        /// The Service Collection <see cref="IServiceCollection"/> for the DI.
        /// </summary>
        public IServiceCollection Services { get; }

        /// <summary>
        /// Add Custom Scheduler <see cref="IScheduledJob"/> Job with the Default <see cref="SchedulerOptions"/> options type.
        /// The options are accessible based on the job name that is being specified.
        /// </summary>
        /// <typeparam name="TJob">The type of the job.</typeparam>
        /// <param name="sectionName">The section name for the job configurations. The default value is SchedulerJobs.</param>
        /// <param name="jobName">The name of the job.</param>
        /// <param name="configure">
        /// The action to configure custom options.
        /// This will override the what is in <see cref="IConfiguration"/> providers.
        /// </param>
        /// <returns></returns>
        public IServiceCollection AddJob<TJob>(
            string sectionName = "SchedulerJobs",
            string? jobName = default,
            Action<SchedulerOptions>? configure = default)
            where TJob : class, IScheduledJob
        {
            Services.AddSingleton<IScheduledJob, TJob>();

            AddJobOptions<TJob>(sectionName, jobName, configure);

            return Services;
        }

        /// <summary>
        /// Add Custom Scheduler <see cref="IScheduledJob"/> Job with factory registration and the Default <see cref="SchedulerOptions"/> options type.
        /// The options are accessible based on the job name that is being specified.
        /// </summary>
        /// <typeparam name="TJob">The type of the job.</typeparam>
        /// <param name="factory">The factory registration for the job.</param>
        /// <param name="configure">
        /// The action to configure custom options.
        /// This will override the what is in <see cref="IConfiguration"/> providers.
        /// </param>
        /// <param name="sectionName">The section name for the job configurations. The default value is SchedulerJobs.</param>
        /// <param name="jobName">The name of the job.</param>
        /// <returns></returns>
        public IServiceCollection AddJob<TJob>(
            Func<IServiceProvider, TJob> factory,
            Action<SchedulerOptions>? configure = default,
            string sectionName = "SchedulerJobs",
            string? jobName = default) where TJob : class, IScheduledJob
        {
            Services.AddSingleton(typeof(IScheduledJob), factory);

            AddJobOptions<TJob>(sectionName, jobName, configure);

            return Services;
        }

        /// <summary>
        /// Add Custom Scheduler <see cref="IScheduledJob"/> Job with factory registration and Custom TJobOptions options type.
        /// </summary>
        /// <typeparam name="TJob">The type of the job.</typeparam>
        /// <typeparam name="TJobOptions">The type of the options.</typeparam>
        /// <param name="factory">The factory to register the job with.</param>
        /// <param name="configure">
        /// The action to configure custom options.
        /// This will override the what is in <see cref="IConfiguration"/> providers.
        /// </param>
        /// <param name="sectionName">The section name for the configurations.</param>
        /// <param name="jobName">The name of the job.</param>
        /// <returns></returns>
        public IServiceCollection AddJob<TJob, TJobOptions>(
            Func<IServiceProvider, TJob> factory,
            Action<TJobOptions>? configure = default,
            string sectionName = "SchedulerJobs",
            string? jobName = default)
            where TJob : class, IScheduledJob
            where TJobOptions : SchedulerOptions, new()
        {
            Services.AddSingleton(typeof(IScheduledJob), factory);

            var name = jobName ?? typeof(TJob).Name;

            AddJobOptions(configure, sectionName, name);

            return Services;
        }

        /// <summary>
        /// Add Custom Scheduler <see cref="IScheduledJob"/> Job instance with custom <see cref="SchedulerOptions"/> options.
        /// </summary>
        /// <typeparam name="TJob">The type of the job.</typeparam>
        /// <typeparam name="TJobOptions">The options for the job.</typeparam>
        /// <param name="configure">
        /// The action to configure custom options.
        /// This will override the what is in <see cref="IConfiguration"/> providers.
        /// </param>
        /// <param name="sectionName"></param>
        /// <param name="jobName">The name of the job, use this for options as well.</param>
        /// <returns></returns>
        public IServiceCollection AddJob<TJob, TJobOptions>(
                Action<TJobOptions>? configure = default,
                string sectionName = "SchedulerJobs",
                string? jobName = null)
                where TJob : class, IScheduledJob
                where TJobOptions : SchedulerOptions, new()
        {
            Services.AddSingleton<IScheduledJob, TJob>();

            var name = jobName ?? typeof(TJob).Name;

            AddJobOptions(configure, sectionName, name);

            return Services;
        }

        private void AddJobOptions<TJob>(
            string sectionName = "SchedulerJobs",
            string? jobName = default,
            Action<SchedulerOptions>? configure = null)
             where TJob : class, IScheduledJob
        {
            var name = jobName ?? typeof(TJob).Name;

            Services
              .AddChangeTokenOptions<SchedulerOptions>(
              $"{sectionName}:{name}",
              name,
              o =>
              {
                  configure?.Invoke(o);
                  o.JobName = name;
              });
        }

        private void AddJobOptions<TJobOptions>(
            Action<TJobOptions>? configure,
            string sectionName,
            string name) where TJobOptions : SchedulerOptions, new()
        {
            // named options used within the job.
            Services
                .AddChangeTokenOptions<TJobOptions>(
                $"{sectionName}:{name}",
                name,
                o =>
                {
                    configure?.Invoke(o);
                    o.JobName = name;
                });

            var so = new Action<SchedulerOptions, IServiceProvider>(
                    (o, sp) =>
                    {
                        var options = sp.GetRequiredService<IOptionsMonitor<TJobOptions>>().Get(name);

                        o.CronSchedule = options.CronSchedule;
                        o.CronTimeZone = options.CronTimeZone;
                        o.RunImmediately = options.RunImmediately;
                        o.JobName = options.JobName;
                    });

            Services
                .AddChangeTokenOptions($"{sectionName}:{name}", name, so);
        }
    }
}
