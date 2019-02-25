using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Polly;
using CronSchedulerApp.Data;
using CronSchedulerApp.Jobs;
using CronSchedulerApp.Services;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc.ViewFeatures;

namespace CronSchedulerApp
{
    public class Startup
    {
        public IConfiguration Configuration { get; }

        private readonly ILogger<Startup> _logger;

        public Startup(IConfiguration configuration, ILogger<Startup> logger)
        {
            Configuration = configuration;
            _logger = logger;
        }

        // This method gets called by the runtime. Use this method to add services to the container.
        public void ConfigureServices(IServiceCollection services)
        {
            // services.AddStartupJob<SeedDatabaseJob>();

            services.AddHttpClient<TorahService>()
                // Build a policy that will handle exceptions, 408s, and 500s from the remote server
                .AddTransientHttpErrorPolicy(p => p.RetryAsync());

            services.Configure<CookiePolicyOptions>(options =>
            {
                // This lambda determines whether user consent for non-essential cookies is needed for a given request.
                options.CheckConsentNeeded = context => true;
                options.MinimumSameSitePolicy = SameSiteMode.None;
            });

            services.AddDbContext<ApplicationDbContext>(options =>
                options.UseSqlServer(
                    Configuration.GetConnectionString("DefaultConnection")));
            services.AddDefaultIdentity<IdentityUser>()
                .AddEntityFrameworkStores<ApplicationDbContext>();

            services
                .AddMvc()
                .SetCompatibilityVersion(CompatibilityVersion.Latest);

            services.AddSingleton<TorahVerses>();

            services.AddScheduler(builder =>
            {
                builder.AddJob<TorahQuoteJob, TorahSettings>();
                builder.UnobservedTaskExceptionHandler = UnobservedHandler;
            });

            //services.AddScheduler((sender, args) =>
            //{
            //    _logger.LogError(args.Exception.Message);
            //    args.SetObserved();
            //});

            services.AddBackgroundQueuedService(applicationOnStopWaitForTasksToComplete:true);

            _logger.LogDebug("Configuration completed");
        }

        private void UnobservedHandler(object sender, UnobservedTaskExceptionEventArgs args)
        {
            _logger.LogError(args.Exception.Message);
            args.SetObserved();
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(IApplicationBuilder app, IHostingEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
                app.UseDatabaseErrorPage();
            }
            else
            {
                app.UseExceptionHandler("/Home/Error");
                app.UseHsts();
            }

            app.UseHttpsRedirection();
            app.UseStaticFiles();
            app.UseCookiePolicy();

            app.UseAuthentication();

            app.UseMvc(routes =>
            {
                routes.MapRoute(
                    name: "default",
                    template: "{controller=Home}/{action=Index}/{id?}");
            });
        }
    }
}
