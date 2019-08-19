using System.Threading.Tasks;

using CronSchedulerApp.Data;
using CronSchedulerApp.Jobs;
using CronSchedulerApp.Services;

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

namespace CronSchedulerApp
{
#pragma warning disable CA1724 // Type names should not match namespaces
    public class Startup
#pragma warning restore CA1724 // Type names should not match namespaces
    {
        private readonly ILogger<Startup> _logger;

        public Startup(IConfiguration configuration, ILogger<Startup> logger)
        {
            Configuration = configuration;
            _logger = logger;
        }

        public IConfiguration Configuration { get; }

        // This method gets called by the runtime. Use this method to add services to the container.
        public void ConfigureServices(IServiceCollection services)
        {
            // Build a policy that will handle exceptions, 408s, and 500s from the remote server
            services.AddHttpClient<TorahService>()
                .AddTransientHttpErrorPolicy(p => p.RetryAsync());

            services.Configure<CookiePolicyOptions>(options =>
            {
                // This lambda determines whether user consent for non-essential cookies is needed for a given request.
                options.CheckConsentNeeded = context => true;
                options.MinimumSameSitePolicy = SameSiteMode.None;
            });

            services.AddDbContext<ApplicationDbContext>(options =>
            {
                if (Configuration["DatabaseProvider:Type"] == "Sqlite")
                {
                    options.UseSqlite(Configuration.GetConnectionString("SqliteConnection"));
                }

                if (Configuration["DatabaseProvider:Type"] == "SqlServer")
                {
                    options.UseSqlServer(Configuration.GetConnectionString("SqlConnection"));
                }
            });
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

            // services.AddScheduler((sender, args) =>
            // {
            //    _logger.LogError(args.Exception.Message);
            //    args.SetObserved();
            // });
            services.AddBackgroundQueuedService(applicationOnStopWaitForTasksToComplete: true);

            _logger.LogDebug("Configuration completed");
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(
            IApplicationBuilder app
#if NETCOREAPP2_2
           , IHostingEnvironment env)
#elif NETCOREAPP3_0
           , IWebHostEnvironment env)
#else
           )
#endif
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
#if NETCOREAPP2_2

            app.UseMvc(routes =>
            {
                routes.MapRoute(
                    name: "default",
                    template: "{controller=Home}/{action=Index}/{id?}");
            });
#elif NETCOREAPP3_0
            app.UseRouting();

            // https://devblogs.microsoft.com/aspnet/blazor-now-in-official-preview/
            app.UseEndpoints(routes =>
            {
                routes.MapControllers();
                routes.MapDefaultControllerRoute();
                routes.MapRazorPages();
            });
#endif
        }

        private void UnobservedHandler(object sender, UnobservedTaskExceptionEventArgs args)
        {
            _logger.LogError(args.Exception.Message);
            args.SetObserved();
        }
    }
}
